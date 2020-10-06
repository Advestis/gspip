#!/bin/bash

BUCKET=${PIP_BUCKET}
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

if [ "$COMMAND" == "" ] ; then
  echo "No command specify. Please provide a command."
  exit 1
fi

if [ "$PACKAGE" == "" ] ; then
  echo "No package specify. Please provide a package."
  exit 1
fi

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
    PACKAGE_LOCATION="gs://$BUCKET/$PACKAGE/"
    return 0
  fi
  if [[ "$PACKAGE" == *"=="* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d"=" -f3)"
    PACKAGE="$(echo "$PACKAGE" | cut -d"=" -f1)"
    comparator="=="
  elif [[ "$PACKAGE" == *">="* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d"=" -f2)"
    PACKAGE="$(echo "$PACKAGE" | cut -d">" -f1)"
    comparator=">="
  elif [[ "$PACKAGE" == *"<="* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d"=" -f2)"
    PACKAGE="$(echo "$PACKAGE" | cut -d"<" -f1)"
    comparator="<="
  elif [[ "$PACKAGE" == *">"* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d">" -f2)"
    PACKAGE="$(echo "$PACKAGE" | cut -d">" -f1)"
    comparator=">"
  elif [[ "$PACKAGE" == *"<"* ]] ; then
    VERSION_TO_GET="$(echo "$PACKAGE" | cut -d"<" -f2)"
    PACKAGE="$(echo "$PACKAGE" | cut -d"<" -f1)"
    comparator="<"
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

function install_from_file() {
  FILE="$PACKAGE"

  echo "Will install packages from file $FILE"
  for line in $(more "$FILE") ; do
    p=$(echo "$line" | cut -d"=" -f1)
    p=$(echo "$p" | cut -d"<" -f1)
    p=$(echo "$p" | cut -d">" -f1)
    if [ "$(echo "$packages_on_gcs" | grep "$p")" == "" ] ; then
      if [ "$UPGRADE" == "yes" ] ; then
        pip install --upgrade "$line"
      else
        pip install "$line"
      fi
    else
      PACKAGE="$line"
      install
    fi
  done

}

function install() {

  format_package

  if [ "$(echo "$packages_on_gcs" | grep "$PACKAGE")" == "" ] ; then
    if [ "$UPGRADE" == "yes" ] ; then
      pip install --upgrade "$PACKAGE$comparator$VERSION_TO_GET"
    else
      pip install "$PACKAGE$comparator$VERSION_TO_GET"
    fi
    exit 0
  fi

  versions=""
  is_installed=$(package_installed)
  local_version=$(installed_version)

  if [ "$is_installed" == "yes" ] && [ "$UPGRADE" == "no" ] && [ "$comparator" == "" ] ; then
    echo "Requirement already satisfied: $PACKAGE ($local_version)"
    return 0
  fi

  # List all version from GCS
  for item in $(gcsls) ; do
    if ! [[ "$item" == *".tar.gz" ]] ; then continue ; fi
    versions="$versions"$'\n'"$(get_version "$item")"
  done

  # Dit not specify a version to get, so get the latest
  if [ "$VERSION_TO_GET" == "" ] ; then

    version_to_install=$(echo "$versions" | sort --version-sort | tail -n 1)

    if [ "$version_to_install" == "" ] ; then
      echo "$SKIP""No package named $PACKAGE found!"
      return 1
    fi

    if [ "$is_installed" == "yes" ] ; then
      loc_and_remote_versions="$local_version"$'\n'"$version_to_install"
      version_to_install=$(echo "$loc_and_remote_versions" | sort --version-sort | tail -n 1)
    fi

  else
    if [ "$comparator" == "==" ] ; then
      version_to_install=$VERSION_TO_GET

    elif [ "$comparator" == ">=" ] ; then
      version_to_install=""
      for v in $versions ; do
        if [ "$v" == "$VERSION_TO_GET" ] ; then
          version_to_install=$VERSION_TO_GET
          break
        elif newer_than "$v" "$VERSION_TO_GET" ; then
          if [ "$version_to_install" == "" ] ; then
            version_to_install=$v
          elif newer_than "$version_to_install" "$v" ; then
            version_to_install=$v
          fi
        fi
      done

    elif [ "$comparator" == "<=" ] ; then
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

    elif [ "$comparator" == ">" ] ; then
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

    elif [ "$comparator" == "<" ] ; then
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
      return 1
    fi
  fi

  if [ "$version_to_install" == "" ] ; then
    echo "No version satisfying the requirements found."
    return 1
  fi
  if [ "$version_to_install" == "$local_version" ] ; then
    echo "Requirement already satisfied: $PACKAGE ($local_version)"
    return 0
  fi

  thefile="$PACKAGE-$version_to_install.tar.gz"

  echo "$SKIP""Will install package $PACKAGE from $PACKAGE_LOCATION$thefile"

  if ! gsutil cp "$PACKAGE_LOCATION$thefile" "/tmp/$thefile" ; then return 1 ; fi
  if ! [ -f "/tmp/$thefile" ] ; then
    echo "No file downloaded!"
    return 1
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
  while [ "$BUCKET" == "" ] ; do
    echo "Bucket was not provided (--bucket argument was not specified, and envvar PIP_BUCKET was not found). Please provide a bucket:"
    read -r BUCKET
    echo "If you want gspip to find your bucket automatically, add the following line to your .bashrc:"
    echo "export PIP_BUCKET=my_bucket_name"
  done
  packages_on_gcs=$(gsutil ls "gs://$BUCKET/")
  packages_on_gcs=${packages_on_gcs//"gs://$BUCKET/"/}
  packages_on_gcs=${packages_on_gcs//"/"/}
  if [ -f "$PACKAGE" ] ; then
    install_from_file
  else
    install
  fi
elif [ "$COMMAND" == "uninstall" ] || [ "$COMMAND" == "remove" ] ; then
  uninstall
elif [ "$COMMAND" == "push" ]  ; then
  push
else
  echo "$SKIP""Unknown command $COMMAND"
fi
