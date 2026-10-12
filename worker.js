// Senatorial is a static site, plus shared pages: a short link (/s/<id>) that always shows the latest version of a
// page, read-only. The page's owner holds a key to update it, which the browser keeps; only a hash of it is stored.

const MAX_MARKDOWN = 512 * 1024;
const MAX_SETTINGS = 8 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    let m;
    if ((m = url.pathname.match(/^\/api\/shares\/([a-z0-9]{6,32})$/))) return api(request, env, m[1]);
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

    // Create the page, or update it with the key it was created with
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
        `INSERT INTO shares (id, token_hash, markdown, settings, created, updated) VALUES (?1, ?2, ?3, ?4, ?5, ?5)
         ON CONFLICT (id) DO UPDATE SET markdown = excluded.markdown, settings = excluded.settings,
           updated = excluded.updated
         WHERE shares.token_hash = excluded.token_hash`,
      )
        .bind(id, hash, body.markdown, settings, now)
        .run();
      if (!result.meta.changes) return json({ error: "wrong key" }, 403);
      return json({ updated: now });
    }

    case "DELETE": {
      const hash = await keyHash(request);
      if (!hash) return json({ error: "missing key" }, 401);
      const result = await env.DB.prepare("DELETE FROM shares WHERE id = ? AND token_hash = ?").bind(id, hash).run();
      if (!result.meta.changes) return json({ error: "not found" }, 404);
      return new Response(null, { status: 204 });
    }

    default:
      return json({ error: "method not allowed" }, 405);
  }
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
