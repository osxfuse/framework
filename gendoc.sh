#!/bin/bash
#
# Generates documentation for the Objective-C framework.
#
# If we don't have a documentation directory, just generate the docs.
if [ ! -d Documentation ]
then
  headerdoc2html -u -o Documentation MacFUSE.hdoc GMUserFileSystem.h GMFinderInfo.h GMResourceFork.h GMAppleDouble.h
  gatherheaderdoc Documentation index.html
exit 0
fi

# We do have a Documentation directory. This probably has .svn subdirs, 
# which will mess up gatherheaderdoc. We do this ugly hack:
if [ -d Documentation.tmp ]
then
  echo "Error: Documentation.tmp exists. Where is your svn directory?"
  exit 1
fi
mv Documentation Documentation.tmp
mkdir Documentation
headerdoc2html -u -o Documentation MacFUSE.hdoc GMUserFileSystem.h GMFinderInfo.h GMResourceFork.h GMAppleDouble.h
gatherheaderdoc Documentation index.html
cp -r Documentation/ Documentation.tmp
rm -rf Documentation
mv Documentation.tmp Documentation
