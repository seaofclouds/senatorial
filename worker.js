// Senatorial is a static site, plus shared pages: a short link (/s/<id>) that always shows the latest version of a
// page, read-only. Pages belong to a desk: a key the browser keeps (and any other browser its link is opened in),
// which can list its pages and update them. Only hashes of keys are stored.

const MAX_MARKDOWN = 512 * 1024;
const MAX_SETTINGS = 8 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    let m;
    if ((m = url.pathname.match(/^\/api\/shares\/([a-z0-9]{6,32})$/))) return api(request, env, m[1]);
    if (url.pathname === "/api/desk") return desk(request, env);
    if (url.pathname === "/api/desk/merge") return mergeDesk(request, env);
    if ((m = url.pathname.match(/^\/s\/([a-z0-9]{6,32})\/?$/))) return sharedPage(request, env, m[1]);
    return env.ASSETS.fetch(request);
  },
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });

const sha256 = async (text) => {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
};

const keyHash = async (request) => {
  const token = (request.headers.get("authorization") ?? "").match(/^Bearer (\S{20,200})$/)?.[1];
  return token ? sha256(token) : null;
};

const getShare = (env, id) =>
  env.DB.prepare("SELECT markdown, settings, updated FROM shares WHERE id = ?").bind(id).first();

async function api(request, env, id) {
  switch (request.method) {
    case "GET": {
      const row = await getShare(env, id);
      if (!row) return json({ error: "not found" }, 404);
      return json({ markdown: row.markdown, settings: JSON.parse(row.settings), updated: row.updated });
    }

    // Create the page, or update it with the key it was created with, or its desk's key. It joins the desk it names.
    case "PUT": {
      const hash = await keyHash(request);
      if (!hash) return json({ error: "missing key" }, 401);
      let body;
      try {
        body = await request.json();
      } catch {
        return json({ error: "bad request" }, 400);
      }
      const settings = JSON.stringify(body?.settings ?? {});
      if (typeof body?.markdown !== "string" || body.markdown.length > MAX_MARKDOWN || settings.length > MAX_SETTINGS)
        return json({ error: "bad request" }, 400);
      const now = Date.now();
      const result = await env.DB.prepare(
        `INSERT INTO shares (id, token_hash, owner_hash, markdown, settings, created, updated)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?6)
         ON CONFLICT (id) DO UPDATE SET markdown = excluded.markdown, settings = excluded.settings,
           updated = excluded.updated, owner_hash = COALESCE(excluded.owner_hash, shares.owner_hash)
         WHERE shares.token_hash = excluded.token_hash OR shares.owner_hash = excluded.token_hash`,
      )
        .bind(id, hash, ownerHash(body), body.markdown, settings, now)
        .run();
      if (!result.meta.changes) return json({ error: "wrong key" }, 403);
      return json({ updated: now });
    }

    // Put the page on a desk, without changing it
    case "PATCH": {
      const hash = await keyHash(request);
      if (!hash) return json({ error: "missing key" }, 401);
      const owner = ownerHash(await request.json().catch(() => null));
      if (!owner) return json({ error: "bad request" }, 400);
      const result = await env.DB.prepare(
        "UPDATE shares SET owner_hash = ?1 WHERE id = ?2 AND (token_hash = ?3 OR owner_hash = ?3)",
      )
        .bind(owner, id, hash)
        .run();
      if (!result.meta.changes) return json({ error: "not found" }, 404);
      return new Response(null, { status: 204 });
    }

    case "DELETE": {
      const hash = await keyHash(request);
      if (!hash) return json({ error: "missing key" }, 401);
      const result = await env.DB.prepare("DELETE FROM shares WHERE id = ?1 AND (token_hash = ?2 OR owner_hash = ?2)")
        .bind(id, hash)
        .run();
      if (!result.meta.changes) return json({ error: "not found" }, 404);
      return new Response(null, { status: 204 });
    }

    default:
      return json({ error: "method not allowed" }, 405);
  }
}

// The desk a page is put on, named by the hash of its key
const ownerHash = (body) => (typeof body?.owner === "string" && /^[0-9a-f]{64}$/.test(body.owner) ? body.owner : null);

// Every page on a desk (that has anything on it), the latest first
async function desk(request, env) {
  if (request.method !== "GET") return json({ error: "method not allowed" }, 405);
  const hash = await keyHash(request);
  if (!hash) return json({ error: "missing key" }, 401);
  const { results } = await env.DB.prepare(
    `SELECT id, markdown, settings, updated FROM shares WHERE owner_hash = ? AND markdown != ''
     ORDER BY updated DESC LIMIT 500`,
  )
    .bind(hash)
    .all();
  return json({
    pages: results.map((row) => ({
      id: row.id,
      title: plainLines(row.markdown)[0] ?? "",
      settings: JSON.parse(row.settings),
      updated: row.updated,
    })),
  });
}

// Move every page on one desk onto another (when a browser takes up another desk, and brings its pages along)
async function mergeDesk(request, env) {
  if (request.method !== "POST") return json({ error: "method not allowed" }, 405);
  const hash = await keyHash(request);
  if (!hash) return json({ error: "missing key" }, 401);
  const into = ownerHash({ owner: (await request.json().catch(() => null))?.into });
  if (!into) return json({ error: "bad request" }, 400);
  const result = await env.DB.prepare("UPDATE shares SET owner_hash = ?1 WHERE owner_hash = ?2").bind(into, hash).run();
  return json({ moved: result.meta.changes });
}

// The page itself, with the shared text built in, and a title & description for link previews
async function sharedPage(request, env, id) {
  const row = await getShare(env, id);
  const shared = row
    ? { id, markdown: row.markdown, settings: JSON.parse(row.settings), updated: row.updated }
    : { id, missing: true };
  const [title, ...rest] = row ? plainLines(row.markdown) : [];
  const description = rest.join(" ").slice(0, 200);

  const page = await env.ASSETS.fetch(new URL("/", request.url).toString());
  const head =
    `<script>window.sharedPage = ${JSON.stringify(shared).replace(/</g, "\\u003c")}</script>` +
    `<meta property="og:type" content="article">` +
    `<meta property="og:title" content="${escapeHtml(title ?? "Senatorial")}">` +
    (description ? `<meta property="og:description" content="${escapeHtml(description)}">` : "") +
    (description ? `<meta name="description" content="${escapeHtml(description)}">` : "");

  return new HTMLRewriter()
    .on("title", {
      element(e) {
        e.setInnerContent(title ? `${title} — Senatorial` : "Senatorial");
        e.before(head, { html: true });
      },
    })
    .on('meta[name="description"]', {
      element(e) {
        if (description) e.remove();
      },
    })
    .transform(
      new Response(page.body, {
        status: row ? 200 : 404,
        headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
      }),
    );
}

// The page's text without its Markdown, a line at a time, skipping blank lines and table delimiter rows
const plainLines = (markdown) =>
  markdown
    .split(/\r?\n|\f/)
    .filter((line) => !/^\s*\|?[\s:|-]*-[\s:|-]*$/.test(line))
    .map((line) =>
      line
        .replace(/^\s*(->)?\s*#*\s*/, "")
        .replace(/\s*(<-|->)\s*$/, "")
        .replace(/<br\s*\/?>/gi, " ")
        .replace(/(\*\*|==|~~~?|[`_*])/g, "")
        .replace(/\\(.)/g, "$1")
        .replace(/^\s*\|\s*|\s*\|\s*$/g, "")
        .replace(/\s*\|\s*/g, " · ")
        .replace(/\s+/g, " ")
        .trim(),
    )
    .filter(Boolean);

const escapeHtml = (s) =>
  s.replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
