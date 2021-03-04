FROM alpine:3.10
LABEL "repository"="https://github.com/anothrNick/github-tag-action"
LABEL "homepage"="https://github.com/anothrNick/github-tag-action"
LABEL "maintainer"="Nick Sjostrom"

RUN apk update && apk add bash git curl jq && apk add --update nodejs npm && npm install -g semver

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
