#!/bin/bash

# Written by Edouard Gouteux 08.2022, based from:
# Marlene Tahedl's BATMAN tutorial, Andrew Jahn,
# and disscussions from https://community.mrtrix.org

# to run after the preprocessing step (we need to have all the files required for this script computed before).

# Compute a map of the mean signal in the b=0 images and divide by the corresponding standard deviation of the b=0 signal 
# Tournier: https://community.mrtrix.org/t/whats-the-minimal-diffusion-directions-for-fba-and-how-to-judge-the-peak-delineation-of-fods/4571/8
# “I will typically measure SNR by extracting the b=0 images, 
# and measuring the temporal #SNR in those images – i.e. the standard deviation 
# of the signal across volumes, divided #by the mean signal. 
# I typically compute this voxel-wise and smooth the resulting image 
# (using a wide median filter for example). This provides a spatial map of 
# the SNR in the #b=0 images, accounting for the fact that on modern 
# multi–channel systems, the SNR is spatially variable. 
# I would normally report the SNR as measured in the periventricular 
# areas since these regions are reasonably representative – the SNR in 
# the periphery will be much higher (closer to the coils), 
# but much lower in the brainstem (much further from #the coils). 
# As to the cut-off value, as mentioned above I would always recommend an 
# SNR of at least 15 in the b=0 images – but more is always better!”

dwiextract -bzero dwi.mif - | mrmath - mean -axis 3 mean_b0_.mif
dwiextract -bzero dwi.mif - | mrmath - std -axis 3 std_b0.mif
mrcalc mean_b0_.mif std_b0.mif -div snr_raw.mif
mrfilter snr_raw.mif median  snr_filtered.mif

# We get a nice brain map with values, we want the values to be 15 or more 
# near strategic parts of the brain for tractography.

# second solution for SNR calculation: 
dwidenoise -noise noise_.mif dwi.SNRmif predwi_denoised.mif
mrstats -output mean -mask mask_preproc_unb.mif noise_.mif        # --> noise
dwiextract -shell 0 predwi_denoised.mif - | mrstats -output mean -mask mask_preproc_unb.mif -allvolumes -        # --> signal in shell b=0
# for us at b0 on one of our data: 64.84

dwiextract -shell 3000 predwi_denoised.mif - | mrstats -output mean -mask mask_preproc_unb.mif -allvolumes -   #--> signal in shell b=3000
# for b3000 on one of our data: 6.91
# recommandation: >5

mrcalc dwi_raw.mif dwi_den.mif -subtract residual.mif

# show the residual
mrview residual.mif

# view the residual for Gibbs effects
mrcalc dwi_den.mif dwi_den_unr.mif –subtract residualUnringed.mif 

mrview dwi_den_unr.mif residualUnringed.mif
mrview residualUnringed.mif 

# In addition, in the "tmp" directory, we can observe a file called 
# dwi_post_eddy.eddy_outlier_map, which contains strings of 0's and 1's. 
# Each 1 represents a slice that is aberrant, either because of too much motion, 
# eddy currents, or whatever. andysbrainbook by Andrew Jahn provides 
# a code to observe the number of outliers:

cd dwifslpreproc-tmp-K5HBVZ #folder name may vary
totalSlices=`mrinfo dwi.mif | grep Dimensions | awk '{print $6 * $8}'`
totalOutliers=`awk '{ for(i=1;i<=NF;i++)sum+=$i } END { print sum }' dwi_post_eddy.eddy_outlier_map`
echo "If the next number is greater than 10, you may have to reject this subject due to excessive movement or corrupted slices."
echo "scale=5; ($totalOutliers / $totalSlices * 100)/1" | bc | tee percentageOutliers.txt

# use of dwibiascorrect: once the command is complete, examine the output to see how the eddy current 
# correction and debriding have changed the data; ideally, you should see more signal restored in 
# regions such as the orbitofrontal cortex, which is particularly sensitive to signal loss. 
# We expect to see a noticeable difference between the two images, especially in the frontal 
# lobes of the brain near the eyes, which are most sensitive to eddy currents. 

mrview dwi_den_preproc_unbiased.mif  -overlay.load dwi_AP.mif 

#inspection of the mask:
mrview mask_preproc_unb.mif

#response function inspection:
shview response.txt

mrview vf_.mif –odf.load_sh wmfod_algorithme.mif
