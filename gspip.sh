#!/bin/bash

BUCKET="pypi_server_sand"
SKIP=""
UPGRADE="no"
VERSION_TO_GET=""

while true; do
  case "$1" in
    -b | --bucket) BUCKET="$2"; shift 2 ;;
    -s | --skip) SKIP="$2"; shift 2 ;;
    -v | --version) VERSION_TO_GET="$2"; shift 2 ;;
    -u | --upgrade) UPGRADE="yes"; shift 1 ;;
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

function get_version() {
  v=$1
  v=${v//"$PACKAGE_LOCATION$PACKAGE-"/}
  v=${v//".tar.gz"/}
  echo "$SKIP""$v"
}

function package_installed() {
  if [ "$(pip freeze | grep "$PACKAGE")" == "" ] ; then
    echo "no"
    return 0
  fi
  echo "yes"
}

function installed_version() {
  if [ "$(package_installed)" == "no" ] ; then return 0 ; fi
  local_version=$(pip freeze | grep "$PACKAGE" | cut -d"=" -f 3)
  echo "$local_version"
}

function install() {

  versions=$VERSION_TO_GET
  is_installed=$(package_installed)
  local_version=$(installed_version)

  if [ "$is_installed" == "yes" ] && [ "$UPGRADE" == "no" ] ; then
    echo "Requirement already satisfied: $PACKAGE ($local_version)"
    exit 0
  fi

  if [ "$versions" == "" ] ; then

    for item in $(gcsls) ; do
      if ! [[ "$item" == *".tar.gz" ]] ; then continue ; fi
      version=$(get_version "$item")
      if [[ "$version" == *"latest"* ]] ; then
        thefile="$PACKAGE-$version.tar.gz"
        break
      fi

      versions="$versions"$'\n'"$version"
    done

    latest_version=$(echo "$SKIP""$versions" | sort --version-sort | tail -n 1)

    if [ "$latest_version" == "" ] ; then
      echo "$SKIP""No package named $PACKAGE found!"
      exit 1
    fi

    if [ "$is_installed" == "yes" ] ; then
      loc_and_remote_versions="$local_version"$'\n'"$latest_version"
      newest=$(echo "$loc_and_remote_versions" | sort --version-sort | tail -n 1)
      if [ "$newest" == "$local_version" ] ; then
        echo "Requirement already satisfied: $PACKAGE ($local_version)"
        exit 0
      fi
    fi

    thefile="$PACKAGE-$latest_version.tar.gz"
  else
    thefile="$PACKAGE-$versions.tar.gz"
  fi

  echo "$SKIP""Will install package $PACKAGE from $PACKAGE_LOCATION$thefile"

  if ! gsutil cp "$PACKAGE_LOCATION$thefile" "/tmp/$thefile" ; then exit 1 ; fi
  if ! [ -f "/tmp/$thefile" ] ; then
    echo "No file downloaded!"
    exit 1
  fi
  pip install "/tmp/$thefile"
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