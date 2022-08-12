#!/bin/bash
# Apply preprocessing script to all the subjects. 
# To run from path just before /subjectX.
# requires file names to be named as:
# ${sub}_ses-preop_acq-AP_dwi.nii.gz,..., ${sub}_ses-preop_T1w.nii.gz 
# with ${sub} (c.f line 25) being the participant code.
# based on the tutorial:
# https://andysbrainbook.readthedocs.io/en/latest/MRtrix/MRtrix_Course

$DIRECTORIES = `ls`

# Apply preprocessing script to all directories, each directory represent one subject.

for sub in $DIRECTORIES ; do
      # copy all bash scripts to the subdirectory corresponding to the subject.
      cp *.sh ${sub}

      # go to this subdirectory.
      cd ${sub};

      # print subject directory.
      subject_directory = $(pwd)
      print "preprocessing directory: $subject_directory"

      # Run the preprocessing script for this subject in the directory.
      bash MRtrix_Preproc_AP_Direction.sh ${sub}_ses-preop_acq-AP_dwi.nii.gz ${sub}_ses-preop_acq-PA_dwi.nii.gz \
        ${sub}_ses-preop_acq-AP_dwi.bvec ${sub}_ses-preop_acq-AP_dwi.bval \
        ${sub}_ses-preop_acq-PA_dwi.bvec ${sub}_ses-preop_acq-PA_dwi.bval \
        ${sub}_ses-preop_T1w.nii.gz
        
      # get back to main directory
      cd ..
done

# Apply quality check for each directory

$DIRECTORIES = `ls`

for sub in $DIRECTORIES ; do

      cd ${sub};
      subject_directory = $(pwd)
      print "Quality check directory: $subject_directory"
      bash Quality_check.sh;
      cd ..;

done
