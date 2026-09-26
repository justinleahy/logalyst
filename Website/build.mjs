// Builds the static site into dist/. The privacy policy is rendered from ../PRIVACY.md so the site and the
// repo never disagree; the other pages are HTML fragments in src/ wrapped in the shared layout below.
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { Marked } from 'marked';

const root = new URL('.', import.meta.url);
const dist = new URL('dist/', root);
const read = (path) => readFileSync(new URL(path, root), 'utf8');

const pages = [
  { path: 'index.html', nav: '', title: 'Logalyst — Health logging for iPhone and Apple Watch', body: read('src/index.html') },
  { path: 'support/index.html', nav: 'support', title: 'Support — Logalyst', body: read('src/support.html') },
  { path: 'privacy/index.html', nav: 'privacy', title: 'Privacy Policy — Logalyst', body: privacyPolicy() },
];

// GitHub-style heading anchors, which the policy's own links (#your-choices, …) rely on.
function privacyPolicy() {
  const slug = (text) => text.toLowerCase().replace(/<[^>]+>/g, '').replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-');
  const marked = new Marked({
    renderer: {
      heading({ tokens, depth }) {
        const text = this.parser.parseInline(tokens);
        return `<h${depth} id="${slug(text)}">${text}</h${depth}>\n`;
      },
    },
  });
  return `<article class="prose">\n${marked.parse(read('../PRIVACY.md'))}</article>`;
}

function layout({ title, nav, body }) {
  const link = (href, name, label) => `<a href="${href}"${nav === name ? ' aria-current="page"' : ''}>${label}</a>`;
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<meta name="description" content="Log blood pressure, glucose, weight, water, food, symptoms and more straight into Apple Health, from your iPhone and Apple Watch.">
<meta name="theme-color" content="#ff3b5a">
<link rel="icon" type="image/png" href="/favicon.png">
<link rel="apple-touch-icon" href="/apple-touch-icon.png">
<link rel="stylesheet" href="/styles.css">
</head>
<body>
<header class="site-header">
  <a class="brand" href="/"><img src="/favicon.png" alt="" width="28" height="28">Logalyst</a>
  <nav>${link('/support/', 'support', 'Support')}${link('/privacy/', 'privacy', 'Privacy')}</nav>
</header>
<main>
${body}
</main>
<footer class="site-footer">
  <p>© ${new Date().getFullYear()} Justin Leahy · <a href="mailto:support@logalyst.app">support@logalyst.app</a></p>
</footer>
</body>
</html>
`;
}

rmSync(dist, { recursive: true, force: true });
cpSync(new URL('public/', root), dist, { recursive: true });
for (const page of pages) {
  const file = new URL(page.path, dist);
  mkdirSync(new URL('.', file), { recursive: true });
  writeFileSync(file, layout(page));
}
console.log(`Built ${pages.length} pages into dist/`);
