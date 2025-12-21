% --- ZAČÁTEK LIMBO SEKCE (LaTeX nastavení) ---
\documentclass[a4paper,11pt]{cweb} % Používáme třídu cweb (součást TeX Live)
\usepackage[utf8]{inputenc}       % Kódování UTF-8
\usepackage[T1]{fontenc}          % Fonty s českými znaky
\usepackage[czech]{babel}         % Česká lokalizace
\usepackage{hyperref}             % Klikací odkazy v PDF
\usepackage{graphicx}             % Pro případné vkládání obrázků

\begin{document}

@* Úvod programu.
Toto je ukázkový \emph{Hello World} program napsaný v systému \textbf{CWEB}.
Ukazuje, jak spojit C++ kód s českou dokumentací vysázenou v \LaTeX u.

Cílem programu je vypsat pozdrav do standardního výstupu.

@c
@<Vložení knihoven@>@;

int main() {
    @<Výpis pozdravu@>;
    return 0;
}

@* Implementace.
Zde detailně popíšeme jednotlivé části kódu. Díky CWEB můžeme kód prezentovat
v logickém pořadí pro čtenáře, ne nutně v pořadí pro kompilátor.

@ Jako první potřebujeme standardní knihovnu pro vstup a výstup.
V C++ se jedná o \texttt{iostream}.

@<Vložení knihoven@>=
#include <iostream>

@ Nyní provedeme samotný výpis.
Použijeme standardní \texttt{std::cout}. Všimněte si, že můžeme používat
české komentáře přímo v kódu, pokud to překladač dovolí, ale v CWEB je lepší
psát komentáře do TeXové části.

@<Výpis pozdravu@>=
std::cout << "Ahoj světe! CWEB s LaTeXem funguje." << std::endl;

@* Rejstřík.
Zde se automaticky vygeneruje seznam použitých identifikátorů.
\end{document}