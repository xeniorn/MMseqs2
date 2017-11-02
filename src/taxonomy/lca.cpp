#include "NcbiTaxonomy.h"
#include "Parameters.h"
#include "DBWriter.h"
#include "FileUtil.h"
#include "Debug.h"
#include "Util.h"

#ifdef OPENMP
#include <omp.h>
#endif

int lca(int argc, const char **argv, const Command& command) {
    Parameters& par = Parameters::getInstance();
    par.parseParameters(argc, argv, command, 3);

#ifdef OPENMP
    omp_set_num_threads(par.threads);
#endif

    DBReader<unsigned int> reader(par.db1.c_str(), par.db1Index.c_str());
    reader.open(DBReader<unsigned int>::LINEAR_ACCCESS);

    std::string nodesFile = par.db2 + "/nodes.dmp";
    std::string namesFile = par.db2 + "/names.dmp";
    if (FileUtil::fileExists(nodesFile.c_str()) && FileUtil::fileExists(namesFile.c_str())) {
    } else if (FileUtil::fileExists("nodes.dmp") && FileUtil::fileExists("names.dmp")) {
        nodesFile = "nodes.dmp";
        namesFile = "names.dmp";
    } else {
        Debug(Debug::ERROR) << "names.dmp and nodes.dmp from NCBI taxdump could not be found!\n";
    }

    DBWriter writer(par.db3.c_str(), par.db3Index.c_str(), par.threads);
    writer.open();

    std::vector<std::string> ranks = Util::split(par.lcaRanks, ":");

    Debug(Debug::INFO) << "Loading NCBI taxonomy...\n";
    NcbiTaxonomy t(namesFile, nodesFile);

    Debug(Debug::INFO) << "Computing LCA...\n";
    size_t entries = reader.getSize();
    #pragma omp parallel
    {
        char *entry[255];
        char buffer[1024];
        #pragma omp for schedule(static)
        for (size_t i = 0; i < entries; ++i) {
            Debug::printProgress(i);
            unsigned int thread_idx = 0;
#ifdef OPENMP
            thread_idx = (unsigned int) omp_get_thread_num();
#endif

            unsigned int key = reader.getDbKey(i);
            char *data = reader.getData(i);
            size_t length = reader.getSeqLens(i);

            if (length == 1) {
                continue;
            }

            std::vector<int> taxa;
            while (*data != '\0') {
                const size_t columns = Util::getWordsOfLine(data, entry, 255);
                if (columns == 0) {
                    Debug(Debug::WARNING) << "Empty entry: " << i << "!";
                    data = Util::skipLine(data);
                    continue;
                }
                int taxon = (int)strtol(entry[0], NULL, 10);
                taxa.emplace_back(taxon);
                data = Util::skipLine(data);
            }

            TaxonNode* node = t.LCA(taxa);

            if (node == NULL) {
                continue;
            }

            if (ranks.empty() == false) {
                std::string lcaRanks = Util::implode(t.AtRanks(node, ranks), ':');
                snprintf(buffer, 1024, "%d\t%s\t%s\t%s\n",
                         node->taxon, node->rank.c_str(), node->name.c_str(), lcaRanks.c_str());
                writer.writeData(buffer, strlen(buffer), key, thread_idx);
            } else {
                snprintf(buffer, 1024, "%d\t%s\t%s\n",
                         node->taxon, node->rank.c_str(), node->name.c_str());
                writer.writeData(buffer, strlen(buffer), key, thread_idx);
            }
        }
    };

    Debug(Debug::INFO) << "\n";

    writer.close();
    reader.close();

    return EXIT_SUCCESS;
}