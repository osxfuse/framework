#!/bin/bash

# Generates documentation for the Objective-C framework.

headerdoc2html -u -o Documentation OSXFUSE.hdoc GMUserFileSystem.h GMFinderInfo.h GMResourceFork.h
gatherheaderdoc Documentation index.html
