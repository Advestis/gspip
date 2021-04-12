#!/bin/bash

BUCKET=$1
PATH_TO_CRED=$2
CRED="-o Credentials:gs_service_key_file=${PATH_TO_CRED}"

cp gspip.sh gspip.sh.tmp

if [ "$BUCKET" != "" ] ; then
  echo "Setting pypi bucket to $BUCKET"
  sed -i "/BUCKET=/c\BUCKET=$BUCKET" gspip.sh.tmp
else
  echo "You did not specify a bucket name. Rerun the command like that : ./install.sh pypi_bucket_name path_cred."
  echo "Ask your code manager if you do not know the bucket name."
  exit 1
fi

if [ "$PATH_TO_CRED" != "" ] ; then
  echo "Setting PATH_TO_CRED to $PATH_TO_CRED"
  sed -i "/PATH_TO_CRED=/c\PATH_TO_CRED=$PATH_TO_CRED" gspip.sh.tmp
else
  echo "You did not specify a path to GCP credentials. Rerun the command like that : ./install.sh pypi_bucket_name path_cred."
  echo "Ask your code manager if you do not know the path."
  exit 1
fi

SCRIPTPATH="$(
  cd "$(dirname "$0")" || {
      echoerr "Could not cd to $(dirname "$0")" ; exit 1
  } >/dev/null 2>&1
  pwd -P
)"

PKG_OK=$(command -v gsutil 2> /dev/null)
if [ "$PKG_OK" = "" ] ; then
  echo "This program requires gsutil to be installed and operationnal."
  exit 1
fi

if ! gsutil $CRED ls gs://$BUCKET &> /dev/null ; then
  echo "Could not talk to GCS : did you specify the correct paths and buckets in the arguments of the command ?"
  echo "I currently have BUCKET=$BUCKET and PATH_TO_CRED=$PATH_TO_CRED."
  exit 1
fi

if [ ! -d "$HOME/bin" ] ; then
  echo "Creating $HOME/bin directory..."
  mkdir "$HOME/bin"
  if [ ! -d "$HOME/bin" ] ; then
      echo "Could not create directory $HOME/bin"
      exit 1
  fi
  echo "...successfully create directory $HOME/bin"
fi

chmod +x "$SCRIPTPATH/"*

if ! [ -d "$HOME/bin" ] ; then
  echo "Creating directory $HOME/bin..."
  mkdir "$HOME/bin"
fi

echo "Copying files to $HOME/bin..."
cp "$SCRIPTPATH/gspip.sh.tmp" "$HOME/bin/gspip"
rm gspip.sh.tmp
if [ ! -f "$HOME/bin/gspip" ] ; then
    echo "Could not copy gspip.sh to $HOME/bin"
    exit 1
fi
echo "  Copied gspip"

echo "...successfully copied files."
source $HOME/.profile