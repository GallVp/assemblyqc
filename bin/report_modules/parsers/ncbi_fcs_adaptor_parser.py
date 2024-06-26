import os
from pathlib import Path
import pandas as pd
from tabulate import tabulate
import re

from report_modules.parsers.parsing_commons import sort_list_of_results


def parse_ncbi_fcs_adaptor_folder(folder_name="ncbi_fcs_adaptor_reports"):
    dir = os.getcwdb().decode()
    reports_folder_path = Path(f"{dir}/{folder_name}")

    if not os.path.exists(reports_folder_path):
        return {}

    list_of_report_files = reports_folder_path.glob("*.txt")

    data = {"NCBI_FCS_ADAPTOR": []}

    for report_path in list_of_report_files:
        report_table = pd.read_csv(report_path, sep="\t")

        file_tokens = re.findall(
            r"([\w]+)\.fcs_adaptor_report.txt",
            os.path.basename(str(report_path)),
        )[0]

        data["NCBI_FCS_ADAPTOR"].append(
            {
                "hap": file_tokens,
                "did_detect_contamination": report_table.shape[0] > 0,
                "report_table": report_table.to_dict("records"),
                "report_table_html": tabulate(
                    report_table,
                    headers=["Accession No.", "Length", "Action", "Range", "Name"],
                    tablefmt="html",
                    numalign="left",
                    showindex=False,
                ),
            }
        )

    return {"NCBI_FCS_ADAPTOR": sort_list_of_results(data["NCBI_FCS_ADAPTOR"], "hap")}
