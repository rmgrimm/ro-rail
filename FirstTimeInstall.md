

# Introduction #

This page outlines the installation process for Rampage AI Lite. If Rampage AI Lite is already installed, please refer to the [RAIL Update Wiki Page](UpdateInstall.md) instead.

# Required Software #

Rampage AI Lite relies on the use of Subversion (SVN) for distribution. To use SVN and download RAIL, you will first need to install [TortoiseSVN](http://tortoisesvn.net/). The download page can be found at http://tortoisesvn.net/downloads.

You may also use other SVN clients; however, this guide will only give example screenshots using TortoiseSVN.

## Alternate Installation ##

If you do not wish to install a SVN client to download Rampage AI Lite, you may download the latest source files individually at the following URL:

**http://ro-rail.googlecode.com/svn/trunk/**

Please make sure to download all files listed within, and to place them inside of your _USER`_`AI_ directory unmodified. This link will always contain the latest version, and newer files can be downloaded to update a copy of RAIL that was downloaded directly.

_Note: The direct download of Rampage AI Lite from this website is more prone to user error. Because of this, support will not be given for problems related to direct download._

# Step-by-Step Install #

## Before You Begin: Locate your Ragnarok Online directory ##

Before continuing, you will need to locate the directory that Ragnarok Online is installed into. The examples on this website show _C:\Users\Robert\Documents\iRO\_ as the installation directory. Your install directory will probably be different.

The following steps will take place in the _AI_ subdirectory, which should be found inside the Ragnarok Online directory.

_Note: Vista users should not install Ragnarok Online into the_Program Files_directory, because of complications with User Account Control (UAC)._

## Step 1: Remove existing scripts ##

To avoid complications with existing custom AI files, it is recommended to remove any existing _USER`_`AI_ directory. We will shortly add it back through TortoiseSVN.

![http://ro-rail.googlecode.com/svn/wiki/img/install/step-1.png](http://ro-rail.googlecode.com/svn/wiki/img/install/step-1.png)

## Step 2: Start TortoiseSVN checkout ##

Right click on an open area in your Ragnarok install's AI folder, and select "`SVN Checkout`". This will start the TortoiseSVN client program.

![http://ro-rail.googlecode.com/svn/wiki/img/install/step-2.png](http://ro-rail.googlecode.com/svn/wiki/img/install/step-2.png)

## Step 3: Identify the SVN repository ##

TortoiseSVN will ask for the location of the files to download. The URL of the repository is:
```
http://ro-rail.googlecode.com/svn/trunk/
```

After you enter this, make sure that TortoiseSVN displays the _Checkout directory_ as **_xyz_\AI\USER\_AI**, where _xyz_ is the location of your Ragnarok Online installation. In the example below, my installation is located at _C:\Users\Robert\Documents\iRO_. Yours will likely be different.

_Note: You may also browse the source of Rampage AI Lite online at http://code.google.com/p/ro-rail/source/browse/trunk._

![http://ro-rail.googlecode.com/svn/wiki/img/install/step-3.png](http://ro-rail.googlecode.com/svn/wiki/img/install/step-3.png)

## Step 4: RAIL Download Finished ##

Congratulations! RAIL has been downloaded to your computer.

![http://ro-rail.googlecode.com/svn/wiki/img/install/step-4.png](http://ro-rail.googlecode.com/svn/wiki/img/install/step-4.png)

To ensure that Ragnarok Online is using RAIL as the AI script, please type `/hoai` (or `/merai` for mercenaries) until Ragnarok tells you that the script has been customized. `/hoai` and `/merai` changes will take effect the next time the AI is loaded (by teleport/fly wing, map-change, logout-login, etc).