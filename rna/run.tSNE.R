#!/usr/bin/env Rscript

suppressPackageStartupMessages(library("argparse"))

parser <- ArgumentParser()
parser$add_argument("-d", "--designFile", type="character", required=TRUE, help="design matrix file")
parser$add_argument("-i", "--inputFile", type="character", required=TRUE, help="input file")
parser$add_argument("-c", "--cellTypeColorFile", default="/WPS1/zhenglt/work/TCR_chunhong/data/CellType.color", type="character", help="cellTypeColorFile")
parser$add_argument("-e", "--clonotypeFile", type="character", help="clonotype file")
parser$add_argument("-o", "--outDir", type="character", required=TRUE, help="output directory")
parser$add_argument("-n", "--ncore", type="integer", default=10, help="number of cores to use [default %(default)s]")
parser$add_argument("-s", "--sample", type="character", default="SAMPLE", help="sample id  [default %(default)s]")
parser$add_argument("-v", "--verbose", action="store_true", default=FALSE, help="whether verbose mode [default %(default)s]")
parser$add_argument("-l", "--log", action="store_true", default=FALSE, help="whether do log transform [default %(default)s]")
args <- parser$parse_args()

print(args)

out.dir <- args$outDir
sample.id <- args$sample
designFile <- args$designFile
cellTypeColorFile <- args$cellTypeColorFile
inputFile <- args$inputFile
args.log <- args$log
clonotype.file <- args$clonotypeFile
ncore <- args$ncore

#### TEST DATA P0205
#out.dir <- "/WPS1/zhenglt/work/TCR_chunhong/integrated.20150707/hetero/byTCellType/test"
#sample.id <- "P1116"
#designFile <- "/WPS1/zhenglt/work/TCR_chunhong/integrated.20150707/hetero/byTCellType/OUT.scLVM.byTCellType/P1116/sfIgnoreERCC/TC/P1116.designUsed.txt"
#cellTypeColorFile <- "/WPS1/zhenglt/work/TCR_chunhong/data/CellType.color"
#inputFile <- "/WPS1/zhenglt/work/TCR_chunhong/integrated.20150707/hetero/byTCellType/OUT.scLVM.byTCellType/P1116/sfIgnoreERCC/TC/P1116.het.countGeneData.sfNormalized"
#args.log <- TRUE
#clonotype.file <- "/WPS1/zhenglt/work/TCR_chunhong/integrated.20150707/tracer/OUT/P0729/filtered_TCR_summary/P0729.summary.cell.reassigneClonotype.txt"

dir.create(out.dir,recursive = T,showWarnings = F)
source("/Share/BP/zhenglt/02.pipeline/cancer/lib/scRNAToolKit.R")

myDesign<-read.table(designFile,header=T,row.names="sample",check.names=F,colClasses=c("factor","character","factor","factor"))
if(!is.null(cellTypeColorFile) && file.exists(cellTypeColorFile)){
    sampleTypeColor <- read.SampleTypeColor(cellTypeColorFile)
}else{
    sampleTypeColor <- auto.colSet(n=length(unique(myDesign$sampleType)),name="Set1")
    names(sampleTypeColor) <- unique(myDesign$sampleType)
}
print(sampleTypeColor)

in.table <- read.table(inputFile,header = T,sep = "\t",stringsAsFactors = F,check.names = F)
rownames(in.table) <- in.table[,1]
Y <- in.table[,c(-1,-2)]
loginfo(sprintf("before simple filter: %d genes",nrow(Y)))
## filter
f <- apply(Y,1,function(x){ nE <- sum(x>0); return( nE > 5 & nE/length(x) > 0.01 )  })
Y <- Y[f,]
loginfo(sprintf("after simple filter: %d genes",nrow(Y)))
## log transform
if(args.log) { Y <- log2(Y+1) }
clonotype.strict.data <- read.clonotype(in.file = clonotype.file,ctype.col = "C_strict")
print(head(myDesign))
patient.col.list <- patientColorListFromMyDesign(myDesign)

loginfo("... all samples.")

sname <- intersect(rownames(myDesign),colnames(Y))
myDesign <- myDesign[sname,,drop=F]
pca.res <- runPCAAnalysis(Y[,sname],sprintf("%s/%s.het.PCA",out.dir,sample.id),
               myDesign[sname,"sampleType"],sampleTypeColor[names(sampleTypeColor) %in% unique(as.character(myDesign$sampleType))],
               ntop=NULL,main=sample.id)
#q()

tsne.res <- runTSNEAnalysis(Y[,sname],sprintf("%s/%s.het.tSNE",out.dir,sample.id),
                col.points = sampleTypeColor[as.character(myDesign$sampleType)],
                legend=c(names(sampleTypeColor)[names(sampleTypeColor) %in% unique(as.character(myDesign$sampleType))],levels(myDesign$libType)),
                col.legend=c(sampleTypeColor[names(sampleTypeColor) %in% unique(as.character(myDesign$sampleType))],rep("black",length(levels(myDesign$libType)))),
                pch=(as.numeric(myDesign$libType)-1) %% 26,cex=0.7,
                pch.legend=c(rep(16,sum(names(sampleTypeColor) %in% unique(as.character(myDesign$sampleType)))),(seq_along(levels(myDesign$libType))-1) %% 26)
                )
###runNMFAnalysis(Y,sprintf("%s/%s.het.NMF",out.dir,sample.id),
###               myDesign[,"sampleType",drop=F],
###               list(sampleType=sampleTypeColor))
###q()

for(nn in c(50,100,150,200,250,300,350,400,450,500,1000,2000,3000,100000))
{
runHierarchicalClusteringAnalysis(Y[,sname],
                sprintf("%s/%s.het.hclustering.n%s",out.dir,sample.id,ifelse(nn>99999,"All",nn)),
                myDesign[sname,"sampleType"],sampleTypeColor[names(sampleTypeColor) %in% unique(as.character(myDesign$sampleType))],
                clonotype.col=clonotype.strict.data,
                patient.col.list = patient.col.list,
                ntop=nn,
                complexHeatmap.use=TRUE,do.cuttree=T,
                verbose=TRUE,main="Variable Genes")
}

sc3.res <- runSC3Analysis(Y[,sname],sprintf("%s/%s.SC3",out.dir,sample.id),
               myDesign[sname,"sampleType"],sampleTypeColor[names(sampleTypeColor) %in% unique(as.character(myDesign[sname,"sampleType"]))],
               do.log.scale=FALSE,n.cores=ncore)
save(sc3.res,file=sprintf("%s/%s.SC3.RData",out.dir,sample.id))
#####qcAndVizMat(Y,myDesign,out.dir,colSet=sampleTypeColor,intgroup=c("sampleType"),ntop=100000,extra=paste0(".",sample.id),sfilter=NULL, gfilter=NULL)


