# 2020-07-19 08:29 
# elihei  [<eheidari@student.ethz.ch>]
#/Volumes/Projects/scGCN/code/R/scGCNUtils/R/load_experiment.R

#' Load the experiment
#'
#' @description
#' Loads the experiment and write it into a SingleCellExperiment object. Also preprocesses data with `scran`
#'
#' @param tag A string indicating the experiment's tag. Should be name of a folder containing train and test folders each of which including `counts.txt`, `cells.txt`, `genes.txt`.
#' @param ... Any additional arguments.
#'
#' @details `counts.txt` contains the counts matrix, `cells.txt` contains cell ids, `genes.txt` contains gene ids.
#'
#' @author Elyas Heidari
#'
#' @section Additional arguments:
#' \describe{
#' \item{spec}{A string indicating the sapience. possible values = `c('cattle', 'chicken','chimpanzee', 'dog_domestic', 'frog_western clawed', 'human', 'mouse_laboratory','rat', 'zebrafish')`.}
#' \item{log}{A logical indicating whether to log the computation times.}
#' \item{verbose}{A logical indicating whether to print out the computation steps.}
#' }
#'
#' @return A SingleCellExperiment with:
#' \describe{
#' \item{rowData(.)$is_TF}{indicating if the gene corresponding to the row is a transcription factor.}
#' \item{rowData(.)$gene_var}{Modeled variance of the log-expression profiles for each gene, based on `scran::modelGeneVar`.}
#' }
#' @export
#'
#'
#'
#' @importFrom  SingleCellExperiment SingleCellExperiment
#' @importFrom  tidyverse map %>%
#' @importFrom  tictoc toc tic.log
#' @importFrom  scran modelGeneVar logNormCounts
#' @importFrom  future future_map


load_experiment <- function(tag, ...) {
    # set params
    params = list(...)
    if(is.list(params[[1]]))
        params = params[[1]]
    # initialization
    exp_dir    = file.path('data_raw', tag)
    assay_tags = c('train', 'test')
    sce_tag    = paste(format(Sys.Date(), '%Y%m%d'), format(Sys.time(), "%X"), sep='_') %>%
        gsub(':', '', .) %>% 
        paste(tag, ., sep='_')
    sce_state  = 1
    log_tag    = NULL
    if(params$log){
        log_tag = sce_tag
        log_dir = sprintf('.logs/%s.log', log_tag)
        log_dir %>% file.create
        params$log = log_tag
    }
    params %<>% set_params('load_experiment', 1)
    # load a single assay
    load_assay <- function(assay_tag){
        # load data
        assay_dir  = file.path(exp_dir, assay_tag) 
        counts_mat = file.path(assay_dir, 'counts.txt')  %>% readMM
        cells      = file.path(assay_dir, 'cells.txt')   %>% fread %>% c %>% .[[1]]
        genes      = file.path(assay_dir, 'genes.txt')   %>% fread %>% c %>% .[[1]]
        colnames(counts_mat) = cells
        rownames(counts_mat) = genes
        # matrix + metadata --> SCE 
        colData    = file.path(assay_dir, 'colData.txt') %>% fread %>% DataFrame
        rownames(colData) = colData$id
        colData    %<>% .[,setdiff(colnames(colData), 'id')]
        stopifnot(dim(colData)[1] == dim(counts_mat)[2])
        colData$tag = assay_tag
        sce         = SingleCellExperiment(
                        assays=list(counts=counts_mat), 
                        colData=DataFrame(colData))
        rownames(sce) %<>% tolower
        # message
        sprintf('--      read %s with %d cells and %d genes', assay_tag, dim(sce)[2], dim(sce)[1]) %>%
            messagef(verbose=params$verbose, log=log_tag)
        sce 
    }
    # load and merge sces
    sce_list = assay_tags %>% future_map(~load_assay(.x))
    genes    = sce_list   %>% map(rownames) %>% purrr::reduce(intersect)
    sce      = sce_list   %>% map(~.x[genes,]) %>% purrr::reduce(cbind)
    # add rowData
    sce      = logNormCounts(sce)
    tfs      = sprintf(file.path('data_raw','prior/homo_genes_%s.txt'), params$spec) %>%
        fread(header=F) %>% .$V1
    rowData(sce)$is_TF    = rownames(sce) %in% tfs
    rowData(sce)$gene_var = modelGeneVar(sce)
    # define metadata fields
    metadata(sce)$input  = list(train=list(), test=list())
    metadata(sce)$output = list(train=list(), test=list())
    metadata(sce)$vis    = list()
    metadata(sce)$tag    = sce_tag
    metadata(sce)$params$load_experiment = params
    # message
    sprintf('--      return sce %s with %d cells and %d genes', sce_tag, dim(sce)[2], dim(sce)[1]) %>%
        messagef(verbose=params$verbose, log=log_tag)
    # log
    toc(log=TRUE, quiet=TRUE)
    tic_log = tic.log(format = TRUE)
    messagef(tic_log[[length(tic_log)]], verbose=params$verbose, log=params$log)
    sce
}
