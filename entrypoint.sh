#!/bin/bash

set -o pipefail

# config
default_semvar_bump=${DEFAULT_BUMP:-minor}
with_v=${WITH_V:-false}
release_branches=${RELEASE_BRANCHES:-master,main}
custom_tag=${CUSTOM_TAG}
source=${SOURCE:-.}
dryrun=${DRY_RUN:-false}
initial_version=${INITIAL_VERSION:-0.0.0}
tag_context=${TAG_CONTEXT:-repo}
tag_target_branch=${TAG_TARGET_BRANCH:-master}
suffix=${PRERELEASE_SUFFIX:-beta}
verbose=${VERBOSE:-true}

cd ${GITHUB_WORKSPACE}/${source}

echo "*** CONFIGURATION ***"
echo -e "\tDEFAULT_BUMP: ${default_semvar_bump}"
echo -e "\tWITH_V: ${with_v}"
echo -e "\tRELEASE_BRANCHES: ${release_branches}"
echo -e "\tCUSTOM_TAG: ${custom_tag}"
echo -e "\tSOURCE: ${source}"
echo -e "\tDRY_RUN: ${dryrun}"
echo -e "\tINITIAL_VERSION: ${initial_version}"
echo -e "\tTAG_CONTEXT: ${tag_context}"
echo -e "\tTAG_TARGET_BRANCH: ${tag_target_branch}"
echo -e "\tPRERELEASE_SUFFIX: ${suffix}"
echo -e "\tVERBOSE: ${verbose}"

current_branch=$(git rev-parse --abbrev-ref HEAD)

pre_release="true"
IFS=',' read -ra branch <<< "$release_branches"
for b in "${branch[@]}"; do
    echo "Is $b a match for ${current_branch}"
    if [[ "${current_branch}" =~ $b ]]
    then
        pre_release="false"
    fi
done
echo "pre_release = $pre_release"

git fetch --tags


# If release look for pre-tag on target branch
if $pre_release
then
  tag=$(git tag --list --merged $tag_target_branch --sort=-v:refname | grep -E "^v?[0-9]+.[0-9]+.[0-9]+$" | head -n1)
  pre_tag=$(git tag --list --merged $tag_target_branch --sort=-v:refname | grep -E "^v?[0-9]+.[0-9]+.[0-9]+(-($suffix|alpha))$" | head -n1)
  if [ -z "$pre_tag" ]
  then
    pre_tag=$(git tag --list --merged HEAD --sort=-v:refname | grep -E "^v?[0-9]+.[0-9]+.[0-9]+(-($suffix|alpha))$" | head -n1)
  fi
else
  tag=$(git tag --list --merged $tag_target_branch --sort=-v:refname | grep -E "^v?[0-9]+.[0-9]+.[0-9]+$" | head -n1)
  if [ -z "$tag"]
  then
    tag=$(git tag --list --merged HEAD --sort=-v:refname | grep -E "^v?[0-9]+.[0-9]+.[0-9]+$" | head -n1)
  fi
  pre_tag=""
fi

if [ -z "$tag" ]
then
    log=$(git log --pretty='%B')
    if [ -z "$pre_tag" ]
    then
      # If not tag or pre-tag found use INITIAL_VERSION
      tag="$initial_version"
      pre_tag="$initial_version"
    else
      if $pre_release
      then
        # If only pre-tag found use it if this is a pre-release
        tag=$pre_tag
      else
        # If only pre-tag found remove pre-release suffix
        tag=$(echo $pre_tag | sed -e "s/-.*//")
      fi
    fi

else
    log=$(git log $tag..HEAD --pretty='%B')
fi

echo -e "Existing tag ${tag}"
echo -e "Existing pre-tag ${pre_tag}"


# get current commit hash for tag
tag_commit=$(git rev-list -n 1 $tag)

# get current commit hash
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    echo ::set-output name=tag::$tag
    exit 0
fi

# echo log if verbose is wanted
if $verbose
then
  echo $log
fi

case "$log" in
    *#major* ) new=$(semver -i major $tag); part="major";;
    *#minor* ) new=$(semver -i minor $tag); part="minor";;
    *#patch* ) new=$(semver -i patch $tag); part="patch";;
    *#none* )
        echo "Default bump was set to none. Skipping..."; exit 0;;
    * )
        if [ "$default_semvar_bump" == "none" ]; then
            echo "Default bump was set to none. Skipping..."; exit 0
        else
            base_tag=$(echo $tag | sed -e "s/-.*//")
            echo "Hey -------------------" base_tag
            new=$(semver -i "${default_semvar_bump}" $base_tag); part=$default_semvar_bump
        fi
        ;;
esac

if $pre_release
then
    # Already a prerelease available, bump it
    if [[ "$pre_tag" == *"$new"* ]]; then
        echo "Bumping ${default_semvar_bump}"
        new_pre_tag=$(echo $pre_tag | sed -e "s/-.*//")
        new=$(semver -i "${default_semvar_bump}" $new_pre_tag --preid $suffix)-$suffix; part="$part"
    else
        new="$new-$suffix"; part="pre-$part"
    fi
fi

echo $part

# did we get a new tag?
if [ ! -z "$new" ]
then
	# prefix with 'v'
	if $with_v
	then
		new="v$new"
	fi
fi

if [ ! -z $custom_tag ]
then
    new="$custom_tag"
fi

if $pre_release
then
    echo -e "Bumping tag ${pre_tag}. \n\tNew tag ${new}"
else
    echo -e "Bumping tag ${tag}. \n\tNew tag ${new}"
fi

# set outputs
echo ::set-output name=new_tag::$new
echo ::set-output name=part::$part

#use dry run to determine the next tag
if $dryrun
then
    echo ::set-output name=tag::$tag
    exit 0
fi

echo ::set-output name=tag::$new

## create local git tag
git tag $new

## push new tag ref to github
dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
full_name=$GITHUB_REPOSITORY
git_refs_url=$(jq .repository.git_refs_url $GITHUB_EVENT_PATH | tr -d '"' | sed 's/{\/sha}//g')

echo "$dt: **pushing tag $new to repo $full_name"

git_refs_response=$(
curl -s -X POST $git_refs_url \
-H "Authorization: token $GITHUB_TOKEN" \
-d @- << EOF

{
  "ref": "refs/tags/$new",
  "sha": "$commit"
}
EOF
)

git_ref_posted=$( echo "${git_refs_response}" | jq .ref | tr -d '"' )

echo "::debug::${git_refs_response}"
if [ "${git_ref_posted}" = "refs/tags/${new}" ]; then
  exit 0
else
  echo "::error::Tag was not created properly."
  exit 1
fi
