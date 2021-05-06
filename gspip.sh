#!/bin/bash

BUCKET=""
SKIP=""
UPGRADE="no"
VERSION_TO_GET=""
PATH_TO_CRED=""

while true; do
    case "$1" in
        -b | --bucket) BUCKET="$2"; shift 2 ;;
        -c | --cred) PATH_TO_CRED="$2"; shift 2 ;;
        -s | --skip) SKIP="$2"; shift 2 ;;
        -u | --upgrade) UPGRADE="yes"; shift 1 ;;
        -- ) shift; break ;;
        * ) break ;;
    esac
done

CRED=""
if [ "$PATH_TO_CRED" != "" ] ; then
    CRED="-o Credentials:gs_service_key_file=${PATH_TO_CRED}"
fi

COMMAND=$1
PACKAGE=$2

if [ "$COMMAND" == "" ] ; then
    echo "No command specified. Please provide a command."
    exit 1
fi

if [ "$PACKAGE" == "" ] ; then
    echo "No package specified. Please provide a package."
    exit 1
fi

function gcsls() {
    gsutil $CRED ls "$PACKAGE_LOCATION" 2> /dev/null
}

function get_version() {
    p=${PACKAGE//"-staging"/}
    v=$1
    v=${v//"$PACKAGE_LOCATION$p-"/}
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
        PACKAGE="$line"
        install
    done
}

function install() {

    format_package

    echo "PACKAGE_LOCATION: $PACKAGE_LOCATION"

    versions=""
    is_installed=$(package_installed)
    local_version=$(installed_version)
    USE_CRED="true"

    if [ "$is_installed" == "yes" ] && [ "$UPGRADE" == "no" ] && [ "$comparator" == "" ] ; then
        echo "Requirement already satisfied: $PACKAGE ($local_version)"
        return 0
    fi

    if ! gsutil $CRED ls gs://$BUCKET/ &> /dev/null ; then
        USE_CRED="false"
        if ! gsutil ls gs://$BUCKET/ &> /dev/null ; then
            echo "Could not talk to gs://$BUCKET : do you have the authorisations?"
            exit 1
        fi
    fi

    if [ "$packages_on_gcs" == "" ] ; then
        if [ "$USE_CRED" == "true" ] ; then
            packages_on_gcs=$(gsutil $CRED ls "gs://$BUCKET/")
        else
            packages_on_gcs=$(gsutil ls "gs://$BUCKET/")
        fi
        packages_on_gcs=${packages_on_gcs//"gs://$BUCKET/"/}
        packages_on_gcs=${packages_on_gcs//"/"/}
    fi

    if [ "$(echo "$packages_on_gcs" | grep "$PACKAGE")" == "" ] ; then
        echo "Package $PACKAGE not found on GCS"
        return 1
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

    thefile="${PACKAGE//"-staging"/}-$version_to_install.tar.gz"

    echo "$SKIP""Will install package $PACKAGE from $PACKAGE_LOCATION$thefile"

    if [ "$USE_CRED" == "true" ] ; then
        if ! gsutil $CRED cp "$PACKAGE_LOCATION$thefile" "/tmp/$thefile" ; then return 1 ; fi
    else
        if ! gsutil cp "$PACKAGE_LOCATION$thefile" "/tmp/$thefile" ; then return 1 ; fi
    fi
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

if [ "$COMMAND" == "install" ] ; then
    if [ "$BUCKET" == "" ] ; then
        echo "Bucket was not provided. Specify it with --bucket argument."
        exit 1
    fi
    if [ -f "$PACKAGE" ] ; then
        if ! install_from_file ; then exit 1 ; fi
    else
        if ! install ; then exit 1 ; fi
    fi
  elif [ "$COMMAND" == "uninstall" ] || [ "$COMMAND" == "remove" ] ; then
      if ! uninstall ; then exit 1 ; fi
  else
      echo "$SKIP""Unknown command $COMMAND"
      exit 1
fi