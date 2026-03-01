system("cweave utfpatgen.w");
system("cp utfpatgen.idx output.idx");
system("cp utfpatgen.scn output.scn");

# Redirect pdflatex to pdftex
$pdflatex = 'pdftex %O %S';