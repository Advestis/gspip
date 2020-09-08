#!/bin/bash

BUCKET="pypi_server_sand"
SKIP=""
UPGRADE="no"
VERSION_TO_GET=""

while true; do
  case "$1" in
    -b | --bucket) BUCKET="$2"; shift 2 ;;
    -s | --skip) SKIP="$2"; shift 2 ;;
    -u | --upgrade) UPGRADE="yes"; shift 1 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

COMMAND=$1
PACKAGE=$2

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

function format_package() {
  if ! [[ "$PACKAGE" == *"="* ]] && ! [[ "$PACKAGE" == *">"* ]] && ! [[ "$PACKAGE" == *"<"* ]] ; then
    return 0
  fi
  if [[ "$PACKAGE" == *"=="* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d"=" -f3)"
    PACKAGE="$(echo "$PACKAGE" | cut -d"=" -f1)"
    comparator="equal"
  elif [[ "$PACKAGE" == *">="* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d"=" -f2)"
    PACKAGE="$(echo "$PACKAGE" | cut -d">" -f1)"
    comparator="supequal"
  elif [[ "$PACKAGE" == *"<="* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d"=" -f2)"
    PACKAGE="$(echo "$PACKAGE" | cut -d"<" -f1)"
    comparator="infequal"
  elif [[ "$PACKAGE" == *">"* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d">" -f2)"
    PACKAGE="$(echo "$PACKAGE" | cut -d">" -f1)"
    comparator="sup"
  elif [[ "$PACKAGE" == *"<"* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d"<" -f2)"
    PACKAGE="$(echo "$PACKAGE" | cut -d"<" -f1)"
    comparator="inf"
  else
    echo "Unknown comparator in $PACKAGE"
    exit 1
  fi
  PACKAGE_LOCATION="gs://$BUCKET/$PACKAGE/"
}

function latest_version() {
  echo "$1" | sort --version-sort | tail -n 1
}

# Check if arg 1 is newer than arg 2
function newer_than() {
  vs="$1"$'\n'"$2"
  if [ "$(latest_version "$vs")" == "$1" ] ; then
    return 0
  fi
  return 1
}

function install() {

  format_package

  versions=""
  is_installed=$(package_installed)
  local_version=$(installed_version)

  if [ "$is_installed" == "yes" ] && [ "$UPGRADE" == "no" ] && [ "$comparator" == "" ] ; then
    echo "Requirement already satisfied: $PACKAGE ($local_version)"
    exit 0
  fi

  # List all version from GCS
  for item in $(gcsls) ; do
    if ! [[ "$item" == *".tar.gz" ]] ; then continue ; fi
    versions="$versions"$'\n'"$(get_version "$item")"
  done

  # Dit not specify a version to get, so get the latest
  if [ "$VERSION_TO_GET" == "" ] ; then

    version_to_install=$(echo "$SKIP""$versions" | sort --version-sort | tail -n 1)

    if [ "$version_to_install" == "" ] ; then
      echo "$SKIP""No package named $PACKAGE found!"
      exit 1
    fi

    if [ "$is_installed" == "yes" ] ; then
      loc_and_remote_versions="$local_version"$'\n'"$version_to_install"
      version_to_install=$(echo "$loc_and_remote_versions" | sort --version-sort | tail -n 1)
    fi

  else
    if [ "$comparator" == "equal" ] ; then
      version_to_install=$VERSION_TO_GET

    elif [ "$comparator" == "supequal" ] ; then
      version_to_install=""
      for v in $versions ; do
        if [ "$v" == "$VERSION_TO_GET" ] ; then
          version_to_install=$VERSION_TO_GET
          break
        elif newer_than "$v" "$VERSION_TO_GET" ; then
          if [ "$version_to_install" == "" ] ; then
            version_to_install=$v
          elif newer_then "$version_to_install" "$v" ; then
            version_to_install=$v
          fi
        fi
      done

    elif [ "$comparator" == "infequal" ] ; then
      version_to_install=""
      for v in $versions ; do
        if [ "$v" == "$VERSION_TO_GET" ] ; then
          version_to_install=$VERSION_TO_GET
          break
        elif newer_than "$VERSION_TO_GET" "$v" ; then
          if [ "$version_to_install" == "" ] ; then
            version_to_install=$v
          elif newer_than "$v" "$version_to_install" ; then
            version_to_install=$v
          fi
        fi
      done

    elif [ "$comparator" == "sup" ] ; then
      version_to_install=""
      for v in $versions ; do
        if [ "$v" == "$VERSION_TO_GET" ] ; then
          continue
        elif newer_than "$v" "$VERSION_TO_GET" ; then
          if [ "$version_to_install" == "" ] ; then
            version_to_install=$v
          elif newer_than "$version_to_install" "$v" ; then
            version_to_install=$v
          fi
        fi
      done

    elif [ "$comparator" == "inf" ] ; then
      version_to_install=""
      for v in $versions ; do
        if [ "$v" == "$VERSION_TO_GET" ] ; then
          continue
        elif newer_than "$VERSION_TO_GET" "$v" ; then
          if [ "$version_to_install" == "" ] ; then
            version_to_install=$v
          elif newer_than "$v" "$version_to_install" ; then
            version_to_install=$v
          fi
        fi
      done

    else
      echo "Unknown comparator $comparator"
      exit 1
    fi
  fi

  if [ "$version_to_install" == "" ] ; then
    echo "No version satisfying the requirements found."
    exit 1
  fi
  if [ "$version_to_install" == "$local_version" ] ; then
    echo "Requirement already satisfied: $PACKAGE ($local_version)"
    exit 0
  fi

  thefile="$PACKAGE-$version_to_install.tar.gz"

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