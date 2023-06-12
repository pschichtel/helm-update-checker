helm-update-checker
===================

This is a simple script that scans a directory tree for `Chart.yaml` files and verifies if all of their dependencies are up to date.
If invalid or outdated versions are found, then the script will exit with code 1.

The main purpose of this script is to be run as a scheduled job in gitlab-ci. The job will fail if any dependencies are outdated.

Usage
-----

The script takes one optional parameter: the path where to look for `Chart.yaml` files.

