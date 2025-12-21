# Toto říká Overleafu: pokud vidíš soubor .w, použij cweave k výrobě .tex
add_cus_dep('w', 'tex', 0, 'w2tex');

sub w2tex {
    # Spustí cweave na vstupní soubor
    system("cweave \"$_[0].w\"");
}