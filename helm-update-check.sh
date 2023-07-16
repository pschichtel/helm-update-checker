#!/usr/bin/env bash

set -euo pipefail

base="${1:-"."}"

shopt -s globstar

max_versions="${MAX_VERSIONS:-5}"
helm_repo_file="${HELM_REPO_FILE:-"$(mktemp)"}"
helm_repo_cache="${HELM_REPO_CACHE:-"$(mktemp -d)"}"
mkdir -p "$helm_repo_cache"

helm_command=(helm --repository-cache "$helm_repo_cache" --repository-config "$helm_repo_file")

problems=()

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

            repo_name="$(echo -n "$repo" | md5sum | cut -d' ' -f1)"
            if ! "${helm_command[@]}" repo add "$repo_name" "$repo" > /dev/null
            then
                echo "    failed to add repository!"
                problems+=("$name:$version from $repo: Failed to add repo")
                continue
            fi

            all_versions="$("${helm_command[@]}" search repo "$repo_name/$name" --versions -o json)"
            matching_versions="$("${helm_command[@]}" search repo "$repo_name/$name" --version "$version" --versions -o json)"

            versions_query='map(.version) | map(select(test($version_pattern // "^.*$")))'
            applicable_versions="$(jq --argjson version_pattern "$version_pattern" "$versions_query" <<< "$all_versions")"
            assumed_version="$(jq -r --argjson version_pattern "$version_pattern" "$versions_query | first" <<< "$matching_versions")"

            if [ "$assumed_version" = "null" ]
            then
                echo "    unknown version '$version', some available versions: $(jq -r --argjson max_versions "$max_versions" '.[0:([$max_versions, length] | min)] | join(", ")' <<< "$applicable_versions")" >&2
                problems+=("$name:$version from $repo: Unknown version, latest valid would be: $(jq -r '.[0]' <<< "$applicable_versions")")
                continue
            fi

            version_index="$(jq -r --arg version "$assumed_version" '. | index($version)' <<< "$applicable_versions")"

            if [ "$version_index" -gt 0 ]
            then
                echo "    version '$version' ('$assumed_version' specifically) is superceded by these versions: $(jq -r --argjson index "$version_index" --argjson max_versions "$max_versions" '.[0:([$max_versions, $index] | min)] | join(", ")' <<< "$applicable_versions")" >&2
                problems+=("$name:$version from $repo: Superceded, latest is: $(jq -r '.[0]' <<< "$applicable_versions")")
            else
                echo "    version '$assumed_version' is up to date!"
            fi
        done
    fi
done

if [ "${#problems[@]}" -gt 0 ]
then
    echo ""
    echo "Problems:"
    for problem in "${problems[@]}"
    do
        echo " * $problem"
    done
    exit 1
fi

