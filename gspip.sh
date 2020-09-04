#!/bin/bash

BUCKET="pypi_server_sand"
SKIP=""
VERSION_TO_GET=""

while true; do
  case "$1" in
    -b | --bucket) BUCKET="$2"; shift 2 ;;
    -s | --skip) SKIP="$2"; shift 2 ;;
    -v | --version) VERSION_TO_GET="$2"; shift 2 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

COMMAND=$1
PACKAGE=$2
PACKAGE_LOCATION="gs://$BUCKET/$PACKAGE/"

function gcsls() {
  gsutil ls "$PACKAGE_LOCATION" 2> /dev/null
}

function get_version {
  v=$1
  v=${v//"$PACKAGE_LOCATION$PACKAGE-"/}
  v=${v//".tar.gz"/}
  echo "$SKIP""$v"
}

function install() {

  versions=$VERSION_TO_GET
  if [ "$versions" == "" ] ; then
    for item in $(gcsls) ; do
      if [[ "$version" == *"latest"* ]] ; then
        thefile="$PACKAGE-$version.tar.gz"
        break
      fi

      version=$(get_version "$item")
      versions="$versions"$'\n'"$version"
    done

    latest_version=$(echo "$SKIP""$versions" | sort --version-sort | tail -n 1)

    if [ "$latest_version" == "" ] ; then
      echo "$SKIP""No package named $PACKAGE found!"
      exit 1
    fi

    thefile="$PACKAGE-$latest_version.tar.gz"
  else
    thefile="$PACKAGE-$versions.tar.gz"
  fi

  echo "$SKIP""Will install package $PACKAGE from $PACKAGE_LOCATION$thefile"

  if ! gsutil cp "$PACKAGE_LOCATION$thefile" "/tmp/$thefile" ; then exit 1 ; fi
  if ! pip install "/tmp/$thefile" ; then rm "/tmp/$thefile" ; fi
  rm "/tmp/$thefile"
}

function uninstall() {
  echo "$SKIP""Will remove package $PACKAGE"
  if ! pip uninstall "$PACKAGE" ; then exit 1 ; fi
}

function recreate_dist() {
  if ! [ -f "setup.py" ] ; then
    echo "$SKIP""Could not find a setup.py file in install any pacakge."
    return 1
  fi
  if ! python setup.py sdist ; then
    return 1
  fi
  if [ -d "build" ] ; then rm -r build ; fi
  if ls "$PACKAGE".egg-info* &> /dev/null ; then rm -r "$PACKAGE".egg-info* ; fi

  if [ ! -d dist ] ; then
    echo "$SKIP""Could not create dist ??"
    return 1
  fi
  thefile=$(find dist/* | grep ".tar.gz" | head -n 1)
  if [ "$thefile" == "" ] ; then
    echo "$SKIP""No .tar.gz file produced!"
    return 1
  fi
  return 0
}

function push() {

  PACKAGE=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]')

  if [ -d dist ] ; then
    thefile=$(find dist/* | grep ".tar.gz" | head -n 1)
    if [ "$thefile" == "" ] ; then
      echo "$SKIP""No .tar.gz in dist. Recreating..."
      if ! recreate_dist ; then
        exit 1
      fi
    fi
  else
    echo "$SKIP""No dist directory. Recreating..."
    if ! recreate_dist ; then
      exit 1
    fi
  fi

  echo "$SKIP""Will now push $PACKAGE to gcs."
  if ! gsutil cp "$thefile" "gs://$BUCKET/$PACKAGE/" ; then
    exit 1
  fi
  if [ -d "dist" ] ; then rm -r dist ; fi
}

if [ "$COMMAND" == "install" ] ; then
  install
elif [ "$COMMAND" == "uninstall" ] || [ "$COMMAND" == "remove" ] ; then
  uninstall
elif [ "$COMMAND" == "push" ]  ; then
  push
else
  echo "$SKIP""Unknown command $COMMAND"
fi