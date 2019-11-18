#!/usr/bin/env nextflow

params.contigFiles = './test_data/s{1,2}/filtered_contig_annotations.csv'
params.consensusFiles = './test_data/s{1,2}/consensus_annotations.json'
params.barcodePrefixes = ['Sample_1_', 'Sample_2_']

params.outFolder = "$workflow.projectDir/reports/test"
params.packageFolder = "$workflow.projectDir/lib"
params.condaEnvPy = 'envs/tcrpy3.yml'
params.condaEnvR = 'envs/tcrpy_r.yml'

params.includeCDRdistances = 'True' //'False'
params.distanceDisambiguation = 'minimum'
params.numCore = 4

Channel
    .fromPath(params.contigFiles)
    .set {contigFiles}
Channel
    .fromPath(params.consensusFiles)
    .set {consensusFiles}
Channel
    .from(params.barcodePrefixes)
    .set {barcodePrefixes}

Channel
    .from(params.packageFolder)
    .into {packageFolder1; packageFolder2; packageFolder3}

Channel
    .from(params.includeCDRdistances)
    .set {includeCDRdistances}
Channel
    .from(params.distanceDisambiguation)
    .into {distanceDisambiguation1; distanceDisambiguation2}
Channel
    .from(params.numCore)
    .into {numCore1; numCore2}



process parseVDJresults {
    conda params.condaEnvPy

    input:
        file contigFiles
        file consensusFiles
        val barcodePrefixes

    output:
        file 'cells.tsv' into sampleCellTable
        file 'chains.tsv' into sampleChainTable
        file 'cdrs.tsv' into sampleCDR3Table

    script:
        """
        parseVDJ.py $barcodePrefixes $contigFiles $consensusFiles cells.tsv chains.tsv cdrs.tsv
        """
}


sampleCellTable.collectFile(name: 'mergedCells.tsv', keepHeader: true).set{mergedCellTable}
sampleCDR3Table.collectFile(name: 'mergedCDRs.tsv').set{mergedCDR3Table}
sampleChainTable.collectFile(name: 'mergedChains.tsv').set{mergedChainTable}


process callClonotypes {

    conda params.condaEnvPy

    publishDir params.outFolder, mode: 'copy', pattern: '{clonotypeTable.tsv, chainNet.tsv}'

    input:
        file mergedCDR3Table

    output:
        file 'clonotypeTable.tsv' into mappedClonotypes
        file 'additionalCellInfo.tsv' into additionalCellInfo
        file 'chainConvergence.tsv' into chainConvergence
        file 'chainMap.tsv' into chainMap
        file 'chainPairs.tsv' into chainPairs1, chainPairs2, chainPairs3
        file 'chainNet.tsv' into chainNet
        file 'inToDiv.txt' into inToDiv
        file 'inToDist.txt' into inToDis, inToKid

    script:
        """
        callClonotype.py $mergedCDR3Table clonotypeTable.tsv additionalCellInfo.tsv chainConvergence.tsv chainMap.tsv chainPairs.tsv chainNet.tsv inToDiv.txt inToDist.txt
        """
}

process calcKidera {
    conda params.condaEnvR

    input:
        file inToKid
        val packageFolder1

    output:
        file 'chainKideras.tsv' into kideraTable1, kideraTable2

    script:
        """
        kideraCalc.r $inToKid chainKideras.tsv $packageFolder1
        """
}

process calcChainDiversity {
    conda params.condaEnvR

    input:
        file inToDiv
        val packageFolder2

    output:
        file 'chainDiv.tsv' into divTable

    script:
        """
        chainDiversityCalc.r $inToDiv chainDiv.tsv $packageFolder2
        """
}

process cdrDistances {

    cpus params.numCore
    conda params.condaEnvPy
    publishDir params.outFolder, mode: 'copy', pattern: 'cdrSeqDistanceMatrix.h5'

    input:
        file inToDis
        file chainPairs1
        val distanceDisambiguation1
        val numCore1
        val includeCDRdistances

    output:
        file 'cdrSeqDistanceMatrix.h5' into cdrDistances

    when:
        includeCDRdistances == 'True'

    script:
        """
        chainBasedCellDistanceCalculations.py cdrseq $inToDis cdrSeqDistanceMatrix.h5 $numCore1
        chainBasedCellDistanceCalculations.py celldist cdrSeqDistanceMatrix.h5 $chainPairs1 $distanceDisambiguation1 $numCore1
        """
}

process kideraDistances {

    cpus params.numCore
    conda params.condaEnvPy
    publishDir params.outFolder, mode: 'copy', pattern: 'kideraDistanceMatrix.h5'

    input:
        file kideraTable1
        file chainPairs2
        val distanceDisambiguation2
        val numCore2

    output:
        file 'kideraDistanceMatrix.h5' into kideraDistances

    script:
        """
        chainBasedCellDistanceCalculations.py kidera $kideraTable1 kideraDistanceMatrix.h5
        chainBasedCellDistanceCalculations.py celldist kideraDistanceMatrix.h5 $chainPairs2 $distanceDisambiguation2 $numCore2
        """
}

process summarizeChainData {

    conda params.condaEnvPy
    publishDir params.outFolder

    input:
        file chainPairs3
        file divTable
        file kideraTable2
        file chainMap
        file mergedChainTable

    output:
        file 'chainTable.tsv' into sumChainTab

    script:
        """
        summarizeReceptorChainTables.py $chainPairs3 $divTable $kideraTable2 $chainMap $mergedChainTable receptorTable.tsv chainTable.tsv
        """
}

process summarizeCellData {
    conda params.condaEnvPy

    publishDir params.outFolder

    input:
        file mergedCellTable
        file additionalCellInfo

    output:
        file 'cellTable.tsv' into sumCellTab

    script:
        """
        summarizeCellTable.py $mergedCellTable $additionalCellInfo cellTable.tsv
        """
}
