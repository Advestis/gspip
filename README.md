# GSPIP

This will install a command that works almost like pip, except that it will look for packages on GCS. You will need
 Google Cloud SDK installed and set, for gspip will use the *gsutil* command.
 
## Installation

Clone the repository, open a terminal and cd to it. Then run
```
chmod +x ./install.sh
./install.sh BUCKET_NAME PATH_TO_CRED_JSON
```
This will copy gspip.sh into your $HOME/bin directory under the name gspip

Then, open a new terminal and run
```
source .profile
```
## Use

To install a package (say, *adutils*), just run

```
gspip install adutils
```

This will look for the last version of *adutils* stored on

 *gs://BUCKET_NAME/adutils/adutils-\*.tar.gz*

To uninstall a package installed this way, you can either use normal `pip uninstall adutils`
 
If the package you are trying to install **is not on GCS**, then the program will raise an error.

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
