########################################################################################
#
# Prosodic analysis toolkit!  
#
# Loops over intervals on a defined tier; extracts them and measures prosodic features 
# Outputs: .csv file 
# 
#  INTERVAL MEASUREMENTS: 
#
# (1) Duration
# (2) F0 (sampled at 10 equidistant intervals)
# (3) Intensity (avg. over utterance)

#  REQUIREMENTS:
#  (1) .wav file 
#  (2) .TextGrid file (same name as .wav file)
#  (3) .TextGrid has labeled intervals on a target tier*
#		
# 			* Can specify if this target tier is always the same (e.g., target_tier = 2), 
#             or if it needs to be dynamically created (currently; can specify it as the *last* tier) 
# #
#
# MC 3/15/2023 
########################################################################################

# Set up 
#include procedures/get_rate_articulation.praat
include procedures/initializeTable.praat
include procedures/getBasicInfo.praat
include procedures/getPitch.praat
include procedures/getRate.praat

include procedures/addMeasurementsTable.praat
include procedures/adjustPitchRanges.praat
include procedures/setRateParameters.praat
include procedures/getHNR.praat

include procedures/getAlphaRatio.praat




# (1) Define I/O directories #######

form Give the working directories
	comment Give the directory for the .wav files (include final /)
	text directory /Users/michellecohn/Desktop/PNAS_Submission/stimuli_1sg/


#	comment Give the directory for the .textgrids (include final /)
#	text tgdirectory /Users/michellecohn/Desktop/RESEARCH_PROJECT_FOLDERS/DementiaBank/VAS/1_chopped_segments/

	comment Give the outputdirectory for the measurement .csv file (include final /)
	text outputdir /Users/michellecohn/Desktop/PNAS_Submission/

	comment Do you want to use TextGrids?
	optionmenu textgrid 2
       option yes
       option no

	comment Give the string at the end of the TextGrid (if applicable)
	text textgridstring .syllables
 
	comment Give the string at the beginning (if applicable) for speaker ID (used for gender)
	text speakerid

	comment Give subject group info (Appends to end of FILENAME)
	text subject_group acoustic_measurements_1SG
  
	comment Do you want to constrain f0 values based on speakers' gender?
	optionmenu constraingender 1
       option yes
       option no

	comment Indicate if "yes" (constrain based on gender), give current speaker gender
	text gender female

	#comment Do you want to log pitch? ("yes" = log pitch; "no" = keep raw Herz)
   	#text log_pitch no

	comment Set number of (equadistant) pitch measurements to make
   	real numintervals 15

	
endform

target_tier_number = 1


################## INITIALIZE TABLE ############
@initializeTable
@setRateParameters
@adjustPitchRanges


################ (3) Loop through files ################
# (3) Loop through TextGrids in subject subfolders
Create Strings as file list...  list 'directory$'/'speakerid$'*.wav
n_wav = Get number of strings

table_row_counter = 1

for ifile from 1 to n_wav
#for ifile from 1 to 2
	select Strings list
	curr_file$ = Get string... 'ifile'
   	Read from file... 'directory$'/'curr_file$'

	soundid = selected("Sound")

   	# Here we make a variable called "object_name$" that will be equal to the filename minus the ".wav" extension
   	object_name$ = selected$ ("Sound")
	wavfile$ = curr_file$ - ".wav" 

	if textgrid == 1
		Read from file... 'tgdirectory$'/'wavfile$''textgridstring$'.TextGrid
		textgridid = selected("TextGrid")

		selectObject: "TextGrid 'object_name$'_syllables"

	endif
	
	
	@getBasicInfo

	@getPitch

	@getRate

	@getHNR

	@getAlphaRatio 

	@addMeasurementsTable


			
select all 
minus Strings list
minus Table acoustic_measurements
Remove

# Fileloop
endfor

selectObject: "Table acoustic_measurements"
Save as comma-separated file: "'outputdir$'acoustic_measurements'subject_group$'.csv"
