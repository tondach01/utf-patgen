# Directive to Overleaf: if you see .w file, use cweave and make .tex
add_cus_dep('w', 'tex', 0, 'w2tex');

sub w2tex {
    # Runs cweave on input
    system("cweave \"$_[0].w\"");
}