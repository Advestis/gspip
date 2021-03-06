#!/bin/bash

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

if ! gsutil ls gs:// &> /dev/null ; then
  echo "Could not talk to GCS : did you properly set up Google Cloud SDK ? Is your current profile set up on the appropriate project ?"
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
cp "$SCRIPTPATH/gspip.sh" "$HOME/bin/gspip"
if [ ! -f "$HOME/bin/gspip" ] ; then
    echo "Could not copy gspip.sh to $HOME/bin"
    exit 1
fi
echo "  Copied gspip"

echo "...successfully copied files."
source $HOME/.profile