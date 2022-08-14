#!/bin/bash

include()
{
    include_file=$1

    source ${include_file}.sh
}