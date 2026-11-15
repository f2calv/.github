import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11.12.1/dist/mermaid.esm.min.mjs';

for (const code of document.querySelectorAll('pre > code.language-mermaid')) {
  const diagram = document.createElement('div');
  diagram.className = 'mermaid';
  diagram.textContent = code.textContent;
  code.parentElement.replaceWith(diagram);
}

mermaid.initialize({ startOnLoad: true, securityLevel: 'strict' });
