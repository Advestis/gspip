# GSPIP

This will install a command that works almost like pip, except that it will look for packages on Advestis/s GCS
 bucket named pypi_server_sand
 
## Installation

Clone the reposirory, open a terminal and cd to it. Then run
```
chmod +x ./install.sh
./install.sh
```

## Use

To install a package (say, AdUtils), just run

```
gspip install adutils
```

This will look for the last version of AdUtils stored on *gs://pypi_server_sand/adutils/adutils-\*.tar.gz*
To uninstall a package installed this way, you can either use normal `pip uninstall adutils` or use `gspip uninstall
 adutils` 

You can also specify a version :

```
gspip install adutils -v 0.11.53
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