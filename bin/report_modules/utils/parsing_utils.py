import os
import pandas as pd
from tabulate import tabulate
import re
import textwrap
from io import StringIO


class Report_Parser:
    def __init__(self, file_data):
        self.file_data = file_data
        self.stats_dict = {}

    def parse_report(self):
        self.stats_dict['version'] = self.get_busco_version(self.file_data)
        self.stats_dict['lineage'] = self.get_lineage_dataset(self.file_data)
        self.stats_dict['created'] = self.get_creation_date(self.file_data)
        self.stats_dict['augustus_species'] = self.get_augustus_species(self.file_data)
        self.stats_dict['mode'] = self.get_run_mode(self.file_data)
        self.stats_dict['predictor'] = self.get_gene_predictor(self.file_data)
        self.stats_dict['search_percentages'] = self.get_busco_percentages(
            self.file_data)
        self.stats_dict['dependencies'] = self.get_deps_and_versions(
            self.file_data)
        self.stats_dict['results_table'] = self.get_busco_result_table(
            self.file_data)

        return self.stats_dict

# parsing functions
# ----------------------------------------------------------------------------------------
    def get_busco_version(self, data):
        p = re.compile("BUSCO version is: (.*)")
        result = p.search(data).group(1).strip()
        return result

    def get_lineage_dataset(self, data):
        p = re.compile("The lineage dataset is: (.*)")
        result = p.search(data).group(1).split()[0]
        return result

    def get_augustus_species(self, file_data):
        list_of_lines = file_data.split('\n')
        length_of_list = len(list_of_lines)
        for index, line in enumerate(list_of_lines):
            if index == length_of_list - 1:
                augustus_species = list_of_lines[length_of_list - 2]
                return augustus_species

    def get_creation_date(self, data):
        p = re.compile("The lineage dataset is: (.*)")
        result = p.search(data)
        result = result.group(1).split()[3][:-1]
        return result

    def get_run_mode(self, data):
        p = re.compile("BUSCO was run in mode: (.*)")
        result = p.search(data).group(1)
        return result

    def get_gene_predictor(self, data):
        p = re.compile("Gene predictor used: (.*)")
        gene_predictor = p.search(data)
        result = gene_predictor.group(1)
        q = re.compile(f"{gene_predictor.group(1)}: (.*)")
        predictor_version = q.search(data)
        return result

    def get_busco_percentages(self, data):
        p = re.compile("C:(.*)")
        result = p.search(data).group(0).strip()
        return result

    def get_deps_and_versions(self, file_data):
        list_of_lines = file_data.split('\n')
        for index, line in enumerate(list_of_lines):
            if "Dependencies and versions" in line:
                all_deps = "".join(
                    list_of_lines[max(0, index + 1): len(list_of_lines)-2]).replace('\t', '\n').strip()

        dep_dict = {}
        for dep in all_deps.splitlines():
            dependency = dep.split(':')[0]
            version = dep.split(':')[1].strip()
            dep_dict[f'{dependency}'] = f'{version}'
        df = pd.DataFrame(dep_dict.items(), columns=[
            'Dependency', 'Version'])

        col_names = ["Dependency", "Version"]
        table = tabulate(df, headers=col_names,
                            tablefmt="html", numalign="left", showindex=False)
        return table

    def get_busco_result_table(self, file_data):
            list_of_lines = file_data.split('\n')
            for index, line in enumerate(list_of_lines):
                if "Dependencies and versions" in line:
                    dev_dep_index = index

            results_dict = {}
            for index, line in enumerate(list_of_lines):
                if "C:" in line:
                    for i in range(index+1, dev_dep_index-1):
                        number = list_of_lines[i].split('\t')[1]
                        descr = list_of_lines[i].split('\t')[2]

                        results_dict[f'{descr}'] = f'{number}' 
            df = pd.DataFrame(results_dict.items(), columns=['Event', 'Frequency'])
            col_names = ["Event", "Frequency"]
            table = tabulate(df, headers=col_names, tablefmt="html", numalign="left", showindex=False)
            return table
# ----------------------------------------------------------------------------------------
# end of parsing functions
