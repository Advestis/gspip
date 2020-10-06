# GSPIP

This will install a command that works almost like pip, except that it will look for packages on GCS. You will need
 Google Cloud SDK installed and set, for gspip will use the *gsutil* command.
 
## Installation

Clone the repository, open a terminal and cd to it. Then run
```
chmod +x ./install.sh
./install.sh
```
This will copy gspip.sh into your $HOME/bin directory under the name gspip

## Use

To install a package (say, *adutils*), just run

```
gspip --bucket bucket_name install adutils
```

This will look for the last version of *adutils* stored on

 *gs://bucket_name/adutils/adutils-\*.tar.gz*

The bucket name can be omitted. In that case, you will be prompted for it later. You can also add the line
`PIP_BUCKET=pypi_server_sand` to your .bashrc to automatically detect the bucket name.
 
To uninstall a package installed this way, you can either use normal `pip uninstall adutils` or use `gspip uninstall
 adutils`.
 
If the package you are trying to install **is not on GCS**, then the program will use the standard pip command. So you
can use gspip to install any package. 

You can also specify a version :

```
gspip install adutils==0.11.53
```

or

```
gspip install "adutils>=0.11.53"
```

**WATCH OUT** : if you specify a version using < or >, do not forget to quote the package and version, otherwise
 < or > will be interpreted as flux redirections.

If the package is already installed, gspip will say "requirements already satisfied", unless you specified the
 *--upgrade* option (**BEFORE** *install* : `gspip --upgrade install package`). In that case it will fetch the most
  recent version from GCS. If you already have the newest version, it will still say "requirements already satisfied".

You can also install from a file : 

```
gspip install requirements.txt
```

## For developpers

If you want to create the tar.gz of your project and push it the the pypi bucket, open a terminal and cd to your
 project, then run
 
```
gspip push
```

You can also create a *install.sh* sript that includes it : 

```
#!/bin/bash
publish=false

PACKAGE="adutils"

while true; do
  case "$1" in
    -p | --publish) publish=true ; shift 1 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done

pip3 uninstall "$PACKAGE" -y || echo "No $PACKAGE to uninstall"
pip3 install setuptools
python3 setup.py install
if $publish && [ -f "$HOME/bin/gspip" ] ; then
  gspip push -s "  "
fi
if [ -d "dist" ] ; then rm -r dist ; fi
if [ -d "build" ] ; then rm -r build ; fi
if ls "$PACKAGE".egg-info* &> /dev/null ; then rm -r "$PACKAGE".egg-info* ; fi
```

Then calling

```
./install.sh -p
```

Will install the pacakge locally and push the tar.gz to gcs. If you only want to install without pushing, just drop
 the *-p*
 
## Adding it to your GitHub actions

Not working yet!