#!/usr/bin/env bash

base="${1:-"."}"

shopt -s globstar

failed=false

for chart_file in "$base"/**/Chart.yaml
do
    dependencies="$(yq eval -o json < "$chart_file" | jq '(.dependencies // []) | map({ index: (.repository | sub("/+$"; "") + "/index.yaml"), name: .name, version: .version })')"
    count="$(jq length <<< "$dependencies")"
    if [ "$count" -gt 0 ]
    then
        echo "Helm Chart: $chart_file"

        declare -i i
        i=0
        while [ "$i" -lt "$count" ]
        do
            dependency="$(jq --argjson i "$i" '.[$i]' <<< "$dependencies")"
            index="$(jq -r .index <<< "$dependency")"
            name="$(jq -r .name <<< "$dependency")"
            version="$(jq -r .version <<< "$dependency")"

            echo "  Dependency '$name' in version '$version' from '$index':"

            available_versions="$(curl -sL "$index" | yq eval -o json | jq --arg name "$name" '(.entries[$name] // []) | map(.version)')"
            latest_version="$(jq -r first <<< "$available_versions")"
            version_index="$(jq -r --arg version "$version" '. | index($version)' <<< "$available_versions")"
            if [ "$version_index" = "null" ]
            then
                echo "    unknown version '$version', some available versions: $(jq -r '.[0:5] | join(", ")' <<< "$available_versions")" >&2
                failed=true
            elif [ "$version_index" -gt 0 ]
            then
                echo "    version '$version' is superceded by these versions: $(jq -r --argjson index "$version_index" '.[0:$index] | join(", ")' <<< "$available_versions")" >&2
                failed=true
            else
                echo "    version '$version' is up to date!"
            fi
            i+=1
        done
    fi
done

if [ "$failed" = "true" ]
then
    echo "Some dependencies were not up to date!"
    exit 1
fi

