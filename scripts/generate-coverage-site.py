#!/usr/bin/env python3
import os
import sys
import re
import html

def md_to_html(md_text):
    """
    A minimal regex-based markdown to HTML converter.
    Handles: headings, paragraphs, lists, code blocks, links, and tables.
    """
    # Escaping HTML characters first might break some things, so we do it carefully
    # or rely on specific replacements.
    
    # Simple block-level parsing
    lines = md_text.split('\n')
    html_output = []
    in_list = False
    in_code_block = False
    in_table = False
    
    for i, line in enumerate(lines):
        # Code blocks
        if line.strip().startswith('```'):
            if in_code_block:
                html_output.append('</code></pre>')
                in_code_block = False
            else:
                html_output.append('<pre><code>')
                in_code_block = True
            continue
        
        if in_code_block:
            html_output.append(html.escape(line))
            continue
            
        # Tables
        if '|' in line:
            if not in_table:
                # Check if it's a separator line (contains only |, -, :, and whitespace)
                if re.match(r'^[\s\|:\-]+$', line):
                    continue
                html_output.append('<table>')
                in_table = True
            
            # If it's a separator line, skip it
            if re.match(r'^[\s\|:\-]+$', line):
                continue

            # Process table row
            cells = [c.strip() for c in line.split('|')]
            if cells[0] == '': cells = cells[1:]
            if cells and cells[-1] == '': cells = cells[:-1]
            
            # Determine if it's a header row
            is_header = False
            if i + 1 < len(lines) and re.match(r'^[\s\|:\-]+$', lines[i+1]):
                is_header = True
            
            row_type = 'th' if is_header else 'td'
            
            html_row = '<tr>'
            for cell in cells:
                # Handle links and basic formatting in cells
                cell_content = re.sub(r'\[([^\]]+)\]\(([^\)]+)\)', r'<a href="\2">\1</a>', cell)
                cell_content = re.sub(r'`([^`]+)`', r'<code>\1</code>', cell_content)
                html_row += f'<{row_type}>{cell_content}</{row_type}>'
            html_row += '</tr>'
            html_output.append(html_row)
            continue
        elif in_table:
            html_output.append('</table>')
            in_table = False

        # Headings
        match = re.match(r'^(#{1,6})\s+(.*)', line)
        if match:
            level = len(match.group(1))
            text = match.group(2)
            anchor = text.lower().replace(' ', '-').replace('.', '').replace('/', '')
            html_output.append(f'<h{level} id="{anchor}">{text}</h{level}>')
            continue
            
        # Lists
        match = re.match(r'^[\-\*]\s+(.*)', line)
        if match:
            if not in_list:
                html_output.append('<ul>')
                in_list = True
            text = match.group(1)
            # Basic link and code formatting
            text = re.sub(r'\[([^\]]+)\]\(([^\)]+)\)', r'<a href="\2">\1</a>', text)
            text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
            html_output.append(f'<li>{text}</li>')
            continue
        elif in_list:
            html_output.append('</ul>')
            in_list = False
            
        # Paragraphs
        if line.strip():
            # Basic link and code formatting
            text = re.sub(r'\[([^\]]+)\]\(([^\)]+)\)', r'<a href="\2">\1</a>', line)
            text = re.sub(r'`([^`]+)`', r'<code>\1</code>', text)
            html_output.append(f'<p>{text}</p>')
        else:
            html_output.append('<br>')

    if in_list: html_output.append('</ul>')
    if in_table: html_output.append('</table>')
    if in_code_block: html_output.append('</code></pre>')

    return '\n'.join(html_output)

def parse_coverage_data(md_text):
    sections = []
    
    # Split by H2 sections
    parts = re.split(r'\n##\s+', md_text)
    
    # First part is intro
    intro_md = parts[0]
    
    for part in parts[1:]:
        lines = part.split('\n')
        module_name = lines[0].strip()
        
        # Skip "Package Summary" section as we are generating our own summary
        if module_name == "Package Summary":
            continue
            
        counts = {
            'Parity': 0,
            'Usable': 0,
            'Partial': 0,
            'Fallback': 0,
            'Compile-only': 0,
            'Total': 0
        }
        
        # Look for table rows
        # Format: | API or function | Linux status | Notes |
        for line in lines[1:]:
            if '|' in line and '---' not in line:
                cells = [c.strip() for c in line.split('|')]
                if len(cells) >= 3:
                    # cells[0] is empty if line starts with |
                    # cells[1] is API or function
                    # cells[2] is Linux status
                    status = cells[2]
                    if status in counts:
                        counts[status] += 1
                        counts['Total'] += 1
                    elif status != "Linux status": # Skip header
                        # If it's something else (like Incomplete), we still count it in total if it's a row
                        if status:
                             counts['Total'] += 1
        
        if counts['Total'] > 0:
            sections.append({
                'name': module_name,
                'anchor': module_name.lower().replace(' ', '-').replace('.', '').replace('/', ''),
                'counts': counts
            })
            
    return intro_md, sections

def main():
    md_path = 'docs/apple-package-function-coverage.md'
    if not os.path.exists(md_path):
        print(f"Error: {md_path} not found")
        sys.exit(1)
        
    with open(md_path, 'r') as f:
        md_text = f.read()
        
    intro_md, sections = parse_coverage_data(md_text)
    
    # Try to use markdown-it-py if available, otherwise fallback
    try:
        from markdown_it import MarkdownIt
        md = MarkdownIt()
        intro_html = md.render(intro_md)
        full_html_content = md.render(md_text)
    except ImportError:
        intro_html = md_to_html(intro_md)
        full_html_content = md_to_html(md_text)
        
    # Generate summary table rows
    table_rows = ""
    for s in sections:
        c = s['counts']
        table_rows += f"""
        <tr>
            <td><a href="#{s['anchor']}">{s['name']}</a></td>
            <td>{c['Total']}</td>
            <td>{c['Parity']}</td>
            <td>{c['Usable']}</td>
            <td>{c['Partial']}</td>
            <td>{c['Fallback']}</td>
            <td>{c['Compile-only']}</td>
        </tr>"""

    html_template = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>QuillUI Coverage Matrix</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
            line-height: 1.6;
            color: #24292e;
            max-width: 1012px;
            margin: 0 auto;
            padding: 2rem;
            background-color: #fff;
        }}
        h1, h2, h3 {{ border-bottom: 1px solid #eaecef; padding-bottom: .3em; }}
        table {{
            border-spacing: 0;
            border-collapse: collapse;
            width: 100%;
            margin-bottom: 16px;
        }}
        th, td {{
            padding: 6px 13px;
            border: 1px solid #dfe2e5;
        }}
        tr:nth-child(2n) {{ background-color: #f6f8fa; }}
        code {{
            padding: .2em .4em;
            margin: 0;
            font-size: 85%;
            background-color: rgba(27,31,35,.05);
            border-radius: 3px;
            font-family: ui-monospace,SFMono-Regular,SF Mono,Menlo,Consolas,Liberation Mono,monospace;
        }}
        pre {{
            padding: 16px;
            overflow: auto;
            font-size: 85%;
            line-height: 1.45;
            background-color: #f6f8fa;
            border-radius: 3px;
        }}
        .filter-container {{
            margin-bottom: 20px;
        }}
        #module-filter {{
            padding: 8px;
            width: 100%;
            box-sizing: border-box;
            border: 1px solid #dfe2e5;
            border-radius: 3px;
            font-size: 16px;
        }}
        .summary-table th {{ background-color: #f6f8fa; }}
        a {{ color: #0366d6; text-decoration: none; }}
        a:hover {{ text-decoration: underline; }}
    </style>
</head>
<body>
    <div class="intro">
        {intro_html}
    </div>

    <h2>Package Coverage Summary</h2>
    <div class="filter-container">
        <input type="text" id="module-filter" placeholder="Search module name..." onkeyup="filterModules()">
    </div>
    <table class="summary-table" id="summary-table">
        <thead>
            <tr>
                <th>Module Name</th>
                <th>Total Rows</th>
                <th>Parity</th>
                <th>Usable</th>
                <th>Partial</th>
                <th>Fallback</th>
                <th>Compile-only</th>
            </tr>
        </thead>
        <tbody>
            {table_rows}
        </tbody>
    </table>

    <hr>

    <div class="full-content">
        {full_html_content}
    </div>

    <script>
        function filterModules() {{
            var input, filter, table, tr, td, i, txtValue;
            input = document.getElementById("module-filter");
            filter = input.value.toUpperCase();
            table = document.getElementById("summary-table");
            tr = table.getElementsByTagName("tr");
            for (i = 1; i < tr.length; i++) {{
                td = tr[i].getElementsByTagName("td")[0];
                if (td) {{
                    txtValue = td.textContent || td.innerText;
                    if (txtValue.toUpperCase().indexOf(filter) > -1) {{
                        tr[i].style.display = "";
                    }} else {{
                        tr[i].style.display = "none";
                    }}
                }}
            }}
        }}
    </script>
</body>
</html>
"""

    os.makedirs('docs/site', exist_ok=True)
    with open('docs/site/index.html', 'w') as f:
        f.write(html_template)
    print("Generated docs/site/index.html")

if __name__ == "__main__":
    main()
