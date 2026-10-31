#!/usr/bin/env python3

import argparse
from pathlib import Path
import pandas as pd

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input_htmls", nargs='+', required=True, help="List of sankey HTML files")
    parser.add_argument("--output", default="combined_sankey.html", help="Output HTML file")
    parser.add_argument("--input_emu", nargs='+', required=True, help="List of emu relative abundance tables")
    args = parser.parse_args()
    
    print(f"Combining {len(args.input_htmls)} sankey HTML plots...")
    
    # Extract sample names and read HTML content
    plots = []
    for html_file in sorted(args.input_htmls):
        html_path = Path(html_file)
        # Extract sample name from filename (e.g., barcode01.combined.fastq.UNITE.sankey_plot.html -> barcode01)
        sample_name = html_path.stem.split('.')[0]

        df = pd.DataFrame()
        for tsv_file in sorted(args.input_emu):
            tsv_path = Path(tsv_file)
            sample_name2 = tsv_path.name.split('.')[0]
            if(sample_name2 == sample_name):
                df = pd.read_csv(tsv_path, sep='\t')
                df.columns = df.columns.str.strip().str.lower().str.replace(' ', '_')
                df = df[['tax_id', 'species', 'genus', 'abundance', 'estimated_counts']].fillna('unknown')
                df = df.sort_values(by='abundance', ascending=False)

        html_content2 = df.to_html()

        with open(html_path, 'r') as f:
            html_content = f.read()
        
        plots.append((sample_name, html_content, html_content2))
    
    # Create a tabbed HTML page
    tab_buttons = []
    tab_content = []
    
    for i, (sample_name, html, html2) in enumerate(plots):
        active_class = "active" if i == 0 else ""
        tab_buttons.append(f'<button class="tablinks" onclick="openTab(event, \'{sample_name}\')">{sample_name}</button>')
        
        # Extract the plotly div and script from the individual HTML
        # Look for the plotly script section
        start = html.find('<div id="')
        end = html.rfind('</script>') + len('</script>')
        
        if start != -1 and end > start:
            plot_section = html[start:end]
            # Force consistent width on the plot div
            plot_section = plot_section.replace('<div id="', '<div style="width: 100%;" id="', 1)
        else:
            # Fallback: use the whole body if we can't extract
            plot_section = html
        
        # Extract the plotly div and script from the individual HTML
        start = html.find('<div id="')
        end = html.rfind('</script>') + len('</script>')

        if start != -1 and end > start:
            plot_section = html[start:end]
            plot_section = plot_section.replace(
                '<div id="',
                '<div style="width: 100%;" id="',
                1
            )
        else:
            plot_section = html

        # Ensure dataframe HTML is wrapped so it doesn't break layout
        table_section = f"""
        <div style="margin-top: 20px; overflow-x: auto;">
            <h3>Abundance table</h3>
            {html2 if html2 else "<p>No data available</p>"}
        </div>
        """

        tab_content.append(f"""
        <div id="{sample_name}" class="tabcontent {active_class}">
            <div style="display: flex; flex-direction: column; gap: 20px;">
                <div>
                    {plot_section}
                </div>
                <div>
                    {table_section}
                </div>
            </div>
        </div>
        """)
    
    # Create the final HTML with CSS for tabs
    combined_html = f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Combined Sankey Plots</title>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 10px;
        }}
        .tab {{
            overflow: hidden;
            border-bottom: 1px solid #ccc;
            background-color: #f1f1f1;
            margin-bottom: 20px;
        }}
        .tab button {{
            background-color: inherit;
            float: left;
            border: none;
            outline: none;
            cursor: pointer;
            padding: 14px 16px;
            transition: 0.3s;
            font-size: 14px;
        }}
        .tab button:hover {{
            background-color: #ddd;
        }}
        .tab button.active {{
            background-color: #4CAF50;
            color: white;
        }}
        .tabcontent {{
            display: none;
            padding: 12px 12px;
            border: 1px solid #ccc;
        }}
        .tabcontent.active {{
            display: block;
        }}
        h1 {{
            text-align: center;
            color: #333;
        }}
    </style>
</head>
<body>
    <h1>Combined Sankey Plots ({len(plots)} samples)</h1>
    
    <div class="tab">
        {''.join(tab_buttons)}
    </div>
    
    {''.join(tab_content)}
    
    <script>
        function openTab(evt, tabName) {{
            var i, tabcontent, tablinks;
            
            // Hide all tab contents
            tabcontent = document.getElementsByClassName("tabcontent");
            for (i = 0; i < tabcontent.length; i++) {{
                tabcontent[i].classList.remove("active");
            }}
            
            // Remove active class from all tab buttons
            tablinks = document.getElementsByClassName("tablinks");
            for (i = 0; i < tablinks.length; i++) {{
                tablinks[i].classList.remove("active");
            }}
            
            // Show the current tab and mark button as active
            document.getElementById(tabName).classList.add("active");
            evt.currentTarget.classList.add("active");
        }}
        
        // Auto-activate all tabs on load
        window.addEventListener('load', function() {{
            for (i=0; i < document.getElementsByClassName("tabcontent"); i++){{
                var tabcontent = document.getElementsByClassName("tabcontent")[i];
                if (tabcontent) {{
                    tabcontent.classList.add("active");
                }}
                var tablinks = document.getElementsByClassName("tablinks")[i];
                if (tablinks) {{
                    tablinks.classList.add("active");
                }}

                // Hide current tab contents
                tabcontent.classList.remove("active");
                
                // Remove active class from current tab button
                tablinks.classList.remove("active");
            }}
            // Reload first tab
            var tabcontent = document.getElementsByClassName("tabcontent")[0];
            if (tabcontent) {{
                tabcontent.classList.add("active");
            }}
            var tablinks = document.getElementsByClassName("tablinks")[0];
            if (tablinks) {{
                tablinks.classList.add("active");
            }}
        }});
    </script>
</body>
</html>
'''
    
    with open(args.output, 'w') as f:
        f.write(combined_html)
    
    print(f"Written combined sankey HTML: {args.output}")


if __name__ == "__main__":
    main()
