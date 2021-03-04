set -e

if [ -z "$GITHUB_TOKEN" ]; then
	echo "Set the GITHUB_TOKEN env variable."
	exit 1
fi

repo_fullname=$(jq -r ".repository.full_name" "$GITHUB_EVENT_PATH")

git remote set-url origin https://x-access-token:$GITHUB_TOKEN@github.com/$repo_fullname.git
git config --global user.email "actions@github.com"
git config --global user.name "GitHub Merge Action"


with_v=${WITH_V:-false}
branch=${BRANCH:-develop}
default_semvar_bump=${BUMP:-patch}
suffix=${PRERELEASE_SUFFIX:-alpha}
stage_transition=${STAGE_TRANSITION:-false}
should_bump=${SHOULD_BUMP:-false}
pull_tag_from=${PULL_TAG_FROM:-HEAD}

echo "*** CONFIGURATION ***"
echo -e "\tCURRENT_BRANCH: ${branch}"
echo -e "\tDEFAULT_BUMP: ${default_semvar_bump}"
echo -e "\tSUFFIX: ${suffix}"
echo -e "\tSTAGE_TRANSITION: ${stage_transition}"
echo -e "\tSHOULD_BUMP: ${should_bump}"
echo -e "\tPULL_TAG_FROM: ${pull_tag_from}"

# Check if this is a pre-release branch
pre_release="true"
if [[ "$branch" =~ "master" ]]
then
    pre_release="false"
fi
echo "Pre-release: $pre_release"

#set -o xtrace

git fetch origin $branch
git checkout $branch

# Get latest tag
tag=$(git tag --sort=-creatordate | head -n 1)
# Get latest tag from branch
branch_tag=$(git tag --merged $pull_tag_from --sort=-creatordate | head -n 1)
echo "tag before latest check: $tag, $branch_tag"

if [[ "$branch_tag" == *"$tag"* ]]; then
  tag=$branch_tag
fi

tag_commit=$(git rev-list -n 1 $tag)

# get current commit hash for tag
commit=$(git rev-parse HEAD)

if [ "$tag_commit" == "$commit" ]; then
    echo "No new commits since previous tag. Skipping..."
    exit 0
fi

if [ "$tag" == "latest" ]; then
    tag=$(git tag --sort=-creatordate | head -n 2 | tail -n 1)
fi

tag=$(echo $tag | sed -e "s/-.*//")


echo "tag before update: $tag"

# if there are none or it's still latest or v, start tags at 0.0.0
if [ -z "$tag" ] || [ "$tag" == "latest" ] || [ "$tag" == "v" ]; then
    echo "Tag does not mmatch semver scheme X.Y.Z(-PRERELEASE)(+BUILD). Changing to 0.0.0'"
    tag="0.0.0"
fi

if $should_bump
then
  new=$(semver -i $default_semvar_bump $tag);
else
  new=$tag
fi

if $pre_release
then
  new=$new-$suffix
fi
#
if [ "$new" != "none" ]; then
    # prefix with 'v'
    if $with_v; then
        new="v$new"
    fi
    echo "new tag: $new"

    # push new tag ref to github
    dt=$(date '+%Y-%m-%dT%H:%M:%SZ')
    full_name=$GITHUB_REPOSITORY

    echo "$dt: **pushing tag $new to repo $full_name"

    git tag -a -m "release: ${new}" $new $commit
fi

#git push origin :refs/tags/latest
#git tag -fa -m "latest release" latest $commit
git push --follow-tag