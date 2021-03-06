#!/bin/sh

# Make the directory
# Shallow clone it
# return the sha of the commit

rm -rf [[DESTINATION]]
mkdir -p [[DESTINATION]]
git clone --depth 0 [[GIT_REPOS]] [[DESTINATION]] #>/dev/null 2>&1
cd [[DESTINATION]]
SHA=$(git log --max-count=1 | awk '/commit/ {print $2}')

echo "repos_dir [[DESTINATION]]"
echo "sha $SHA"