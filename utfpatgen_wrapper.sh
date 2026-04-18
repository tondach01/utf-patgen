dictionary="$1"
utfp_dictionary=$dictionary
patterns="$2"
output="$3"
pre_output=$output
translate="$4"

if [ -n "$dictionary" ] && [ -f "$dictionary" ] && [ "$dictionary" -ne "/dev/null" ]; then
    utfp_dictionary=${dictionary}_utfp
    sed -b 's/1/\xFE\x01/g; s/2/\xFE\x02/g; s/3/\xFE\x03/g; s/4/\xFE\x04/g; s/5/\xFE\x05/g; s/6/\xFE\x06/g; s/7/\xFE\x07/g; s/8/\xFE\x08/g; s/9/\xFE\x09/g' $dictionary > $utfp_dictionary
fi
if [ -n "$output" ] && [ "$output" -ne "/dev/null" ]; then
    pre_output=${output}_pre
fi
"$( dirname "${BASH_SOURCE[0]}" )/build/utfpatgen" $utfp_dictionary $patterns $pre_output $translate
if [ -n "$pre_output" ] && [ -f "$pre_output" ]; then
    sed -b 's/\xFE\x01/1/g; s/\xFE\x02/2/g; s/\xFE\x03/3/g; s/\xFE\x04/4/g; s/\xFE\x05/5/g; s/\xFE\x06/6/g; s/\xFE\x07/7/g; s/\xFE\x08/8/g; s/\xFE\x09/9/g' $pre_output > $output
fi
if [[ -n "$utfp_dictionary" ] && [ "$utfp_dictionary" -ne "/dev/null" ]] || [[ -n "$pre_output" ] && [ "$pre_output" -ne "/dev/null" ]]; then
    rm -f $utfp_dictionary $pre_output
fi