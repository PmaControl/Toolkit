#!/bin/bash

# Chaîne de caractères avec des caractères spéciaux
input_string='+ -><()~*:&&|"'
echo $input_string
# Échapper les caractères spéciaux
escaped_string=$(echo "$input_string" | sed 's/"/\\&/g')

# Afficher la chaîne échappée
echo "$escaped_string"
