#!/bin/bash

#inputs required in this order:
RAW_DWI=$1
REV_PHASE=$2
AP_BVEC=$3
AP_BVAL=$4
PA_BVEC=$5
PA_BVAL=$6
ANAT=$7

#Conversion of raw_dwi file to .mif format
mrconvert $RAW_WDI dwi_AP.mif -fslgrad $AP_BVEC $AP_BVAL

# denoising phase
dwidenoise dwi_raw.mif dwi_den.mif -noise noise.mif

# It is possible to increase the noise parameter if there is too much noise. 
# default parameter is 5 for dwidenoise, we could increase the parameter 
# in order to remove more noise:
# dwidenoise dwi_raw.mif dwi_den.mif -extent 7 -noise noise.mif

# remove Gibbs effects:
mrdegibbs dwi_den.mif dwi_den_unr.mif 

# Echo-planar imaging distortion correction:  pre-processing step which aims to 
# correct distortions in the image. We want to obtain a less noisy and more accurate 
# b0 by taking the average of the two images in phase AP and PA at b0. 
mrconvert $REV_PHASE PA.mif

#conversion of reverse-phase file to .mif format
mrconvert PA.mif dwi_PA.mif -fslgrad $PA_BVEC $PA_BVAL

# calculation of mean_b0_AP.mif
dwiextract dwi_den_unr.mif - -bzero | mrmath - mean mean_b0_AP.mif -axis 3
# same for mean_b0_PA.mif
dwiextract dwi_PA.mif - -bzero | mrmath - mean mean_b0_PA.mif -axis 3

# concatenate mean_b0_AP and mean_b0_PA 
mrcat mean_b0_AP.mif mean_b0_PA.mif -axis 3 b0_pair.mif

# apply the Echo-planar imaging distortion correction algorithm
dwifslpreproc dwi_den_unr.mif dwi_preproc.mif -nocleanup -pe_dir AP -rpe_pair -se_epi b0_pair.mif -eddy_options " --slm=linear --data_is_shelled"

# use of "dwibiascorrect": this command allows to remove inhomogeneities detected in 
# the data which can lead to a better estimation of the mask.  However, this may in 
# some cases lead to a poorer estimate

# Before creating a mask we have to correct intensity inhomogeneities in our data 
# in order to avoid holes in the brain mask.

# On dwibiascorrect and dwi2mask, tips for having a good mask from Dhollanders:
# https://community.mrtrix.org/t/dwi2mask-holes-in-mask-images/484/10
# “In practice, a (“reasonable”) approach given what’s currently available in MRtrix is 
# to run dwi2mask first to get an initial mask (i.e. like the one you showed; 
# imperfect but ok’ish at this stage), use that one to call dwibiascorrect, 
# and use the bias corrected result again as an imput to dwi2mask. You could essentially 
# just keep on iterating both to do a close-to-joint optimisation of both, 
# but we find that in practice just doing “initial masking --> bias field correction --> 
# final masking” will get you mostly there in a wide range of scenarios and data qualities.”
dwibiascorrect -ants dwi_den_unr_preproc.mif dwi_den_preproc_unbiased.mif -bias bias.mif

# Brain mask estimation
dwi2mask dwi_preproc_unbiased.mif mask_preproc_unb.mif

# If the mask has too much holes, we could also try using bet2 with fsl 
# to build a mask with custom parameters.

# Why we can use dwi2response dhollander and dwi2fod msmt_csd combo with a single shell, 
# from JDTournier: https://community.mrtrix.org/t/single-shell-dti-data/4468/3
# “since even single-shell data effectively contains 2 shells: the b=0 volumes 
# qualify as a ‘shell’ in this context (we need to update the docs to reflect that… ).
# So you should be able to use your data in more or less exactly the same way as 
# outlined in the BATMAN tutorial, with the only change being the dwi2fod call” 
# i.e we use dhollander for function CSF and WM and then dwi2fod msnt_csd 
# for CSF and WM like in BATMAN.
dwi2response dhollander dwi_preproc_unbiased.mif response.txt -mask mask_preproc_unb.mif
dwi2fod msmt_csd dwi_preproc_unbiased.mif response_wm.txt wmfod.mif response_csf.txt csf.mif - mask mask_preproc_unb.mif

# FOD normalisation
mtnormalise wmfod.mif wmfod_norm.mif csffod.mif csffod_norm.mif -mask mask_preproc_unb.mif
 
# Convert the anatomical image to .mif format, and then extract all five tissue categories (1=GM; 2=Subcortical GM; 3=WM; 4=CSF; 5=Pathological tissue)
mrconvert $ANAT anat.mif 
5ttgen fsl anat.mif 5tt_nocoreg.mif

# The following series of commands will take the average of the b0 images (which have the best contrast), 
# convert them and the 5tt image to NIFTI format, and use it for coregistration.
dwiextract dwi_den_preproc_unbiased.mif - -bzero | mrmath - mean mean_b0_processed.mif -axis 3
mrconvert mean_b0_processed.mif mean_b0_processed.nii.gz
mrconvert 5tt_nocoreg.mif 5tt_nocoreg.nii.gz

# Uses FSL commands fslroi and flirt to create a transformation matrix for registration between the tissue map and the b0 images
fslroi 5tt_nocoreg.nii.gz 5tt_vol0.nii.gz 0 1 #Extract the first volume of the 5tt #dataset (since flirt can only use 3D images, not 4D images)
flirt -in mean_b0_processed.nii.gz -ref 5tt_vol0.nii.gz -interp nearestneighbour -dof 6 -omat diff2struct_fsl.mat
transformconvert diff2struct_fsl.mat mean_b0_processed.nii.gz 5tt_nocoreg.nii.gz flirt_import diff2struct_mrtrix.txt

mrtransform 5tt_nocoreg.mif -linear diff2struct_mrtrix.txt -inverse 5tt_coreg.mif
#Create a seed region along the GM/WM boundary
5tt2gmwmi 5tt_coreg.mif gmwmSeed_coreg.mif

#Streamline analysis
# Create streamlines
# Note that the "right" number of streamlines is still up for debate. MRtrix 
# documentation recommend about 100 million tracks, but we reduce it here in order #to compute faster.
tckgen -act 5tt_coreg.mif -backtrack -seed_gmwmi gmwmSeed_coreg.mif -nthreads 8 -maxlength 250 -cutoff 0.06 -select 10000000 wmfod_norm.mif tracks_10M.tck

# Extract a subset of tracks (here, 200 thousand) for ease of visualization
tckedit tracks_10M.tck -number 200k smallerTracks_200k.tck

# Reduce the number of streamlines with tcksift
tcksift2 -act 5tt_coreg.mif -out_mu sift_mu.txt -out_coeffs sift_coeffs.txt -nthreads 8 tracks_10M.tck wmfod_norm.mif sift_1M.txt
