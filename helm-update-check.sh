#!/usr/bin/env bash

set -euo pipefail

base="${1:-"."}"

shopt -s globstar

failed=false

for chart_file in "$base"/**/Chart.yaml
do
    dependencies="$(yq -o json '.dependencies | map(.version_pattern = (.version | line_comment))' < "$chart_file" | jq 'map({ repo: (.repository | sub("/+$"; "")), name: .name, version: .version, version_pattern: (if .version_pattern == "" then null else .version_pattern end) })')"
    count="$(jq length <<< "$dependencies")"
    if [ "$count" -gt 0 ]
    then
        echo "Helm Chart: $chart_file"

        for i in $(seq 0 "$(("$count" - 1))")
        do
            dependency="$(jq --argjson i "$i" '.[$i]' <<< "$dependencies")"
            repo="$(jq -r .repo <<< "$dependency")"
            name="$(jq -r .name <<< "$dependency")"
            version="$(jq -r .version <<< "$dependency")"
            version_pattern="$(jq .version_pattern <<< "$dependency")"

            echo "  Dependency '$name' in version '$version' from '$repo':"

            if grep -qP '^oci://' <<< "$repo"
            then
                echo "    OCI registries are not currently supported!" >&2
                continue
            fi

            index="$repo/index.yaml"
            available_versions="$(curl -sL "$index" | yq eval -o json | jq --arg name "$name" --argjson version_pattern "$version_pattern" '(.entries[$name] // []) | map(.version) | map(select(test($version_pattern // "^.*$")))')"
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
        done
    fi
done

if [ "$failed" = "true" ]
then
    echo "Some dependencies were not up to date!"
    exit 1
fi

