include_guard(GLOBAL)

configure_file(${MERNEL_ROOT}/cmake/mocWrapper.cmake.in ${CMAKE_BINARY_DIR}/mocWrapper.cmake @ONLY)

# qt5_make_output_file saved from deprecated
# macro used to create the names of output files preserving relative dirs
macro(qt5_make_output_file_patched infile prefix ext outfile )
    string(LENGTH ${CMAKE_CURRENT_BINARY_DIR} _binlength)
    string(LENGTH ${infile} _infileLength)
    set(_checkinfile ${CMAKE_CURRENT_LIST_DIR})
    if(_infileLength GREATER _binlength)
        string(SUBSTRING "${infile}" 0 ${_binlength} _checkinfile)
        if(_checkinfile STREQUAL "${CMAKE_CURRENT_BINARY_DIR}")
            file(RELATIVE_PATH rel ${CMAKE_CURRENT_BINARY_DIR} ${infile})
        else()
            file(RELATIVE_PATH rel ${CMAKE_CURRENT_LIST_DIR} ${infile})
        endif()
    else()
        file(RELATIVE_PATH rel ${CMAKE_CURRENT_LIST_DIR} ${infile})
    endif()
    if(WIN32 AND rel MATCHES "^([a-zA-Z]):(.*)$") # absolute path
        set(rel "${CMAKE_MATCH_1}_${CMAKE_MATCH_2}")
    endif()
    set(_outfile "${CMAKE_CURRENT_BINARY_DIR}/${rel}")
    string(REPLACE ".." "__" _outfile ${_outfile})
    get_filename_component(outpath ${_outfile} PATH)
    get_filename_component(_outfile ${_outfile} NAME_WLE)
    file(MAKE_DIRECTORY ${outpath})
    set(${outfile} ${outpath}/${prefix}${_outfile}.${ext})
endmacro()

function(CreateUiRules outfiles extraIncludes extraPostprocess)
    set(ui_files ${ARGN})
    set(includes)

    foreach(it ${ui_files})
        get_filename_component(outfile ${it} NAME_WE)
        get_filename_component(infile ${it} ABSOLUTE)

        qt5_make_output_file_patched(${it} ui_ h outfile)

        get_filename_component(incl_path ${outfile} PATH)
        
        set(postprocessArgs)
        foreach(cmakeScript ${extraPostprocess})
            list(APPEND postprocessArgs COMMAND ${CMAKE_COMMAND} ARGS -DINPUT=${outfile} -P ${cmakeScript})
        endforeach()

        list(APPEND includes ${incl_path} )
        add_custom_command(OUTPUT ${outfile}
          COMMAND ${QT_CMAKE_EXPORT_NAMESPACE}::uic
          ARGS ${ui_options} -o ${outfile} ${infile}
          ${postprocessArgs}
          MAIN_DEPENDENCY ${infile} VERBATIM)
        list(APPEND ${outfiles} ${outfile})
    endforeach()
    list(REMOVE_DUPLICATES includes)
    set(${outfiles} ${${outfiles}} PARENT_SCOPE)
    set(${extraIncludes} ${includes} PARENT_SCOPE)
endfunction()

# modified QT5_WRAP_CPP
# pathed qt macro to force always have output cpp file. However, it now does not require to run cmake to detect Q_OBJECT macro.
function(CreateMocRules outfiles includes defines)
    string(REPLACE ";" "," includesMoc "${${includes}}")
    string(REPLACE ";" "," definesMoc "${${defines}}")
    foreach(it ${ARGN})
        get_filename_component(it ${it} ABSOLUTE)
        qt5_make_output_file_patched(${it} moc_ cpp outfile)
        add_custom_command(
            OUTPUT ${outfile}
            COMMAND ${CMAKE_COMMAND} -DINFILE=${it} -DOUTFILE=${outfile} -DINCLUDES=${includesMoc} -DDEFINES=${definesMoc} -P ${CMAKE_BINARY_DIR}/mocWrapper.cmake
            DEPENDS ${it}
            VERBATIM)
        list(APPEND ${outfiles} ${outfile})
    endforeach()
    set(${outfiles} ${${outfiles}} PARENT_SCOPE)
endfunction()

# filename - outfile
# fileListName - variable name with list
# basedir - root for replace
# qrcPrefix - prefix for configuration
function(GenerateQrc filename fileListName basedir qrcPrefix)
    foreach (file ${${fileListName}})
        string(REPLACE "${basedir}/" "" file "${file}")
        set(QRC_FILES "${QRC_FILES}<file>${file}</file>\n")
    endforeach()
    configure_file( ${MERNEL_ROOT}/cmake/qrcTemplate.qrc.in ${filename} @ONLY )
endfunction()

function(AddQrcOutput rccName qrcName)
    set(fileListAbsConfig ${ARGN})
    configure_file( ${MERNEL_ROOT}/cmake/qrcTemplate.qrc.in ${qrcName} @ONLY )
    source_group("Qt Resource Files" FILES ${qrcName})
    add_custom_command(OUTPUT ${rccName}
                       COMMAND ${QT_CMAKE_EXPORT_NAMESPACE}::rcc
                       ARGS --no-compress --binary -o ${rccName} ${qrcName}
                       MAIN_DEPENDENCY ${qrcName}
                       DEPENDS ${fileListAbsConfig} VERBATIM)
endfunction()

function(AddQrcTarget qrcPath)
	get_filename_component(filename ${qrcPath} NAME_WE)
	get_filename_component(qrcParent ${qrcPath} PATH)
	set(rccPath ${CMAKE_BINARY_DIR}/assetsCompiled/${filename}.rcc)

	set(fileListAbsConfig)
	file(READ "${qrcPath}" fileContents)
	string(REGEX MATCHALL "<file[^<]+" qrcFiles "${fileContents}")
	string(REGEX REPLACE "<file[^>]*>" "" qrcFiles "${qrcFiles}")
	set(_RC_DEPENDS)
	foreach(name ${qrcFiles})
		list(APPEND fileListAbsConfig "${qrcParent}/${name}")
	endforeach()
	add_custom_command(OUTPUT ${rccPath}
                       COMMAND ${QT_CMAKE_EXPORT_NAMESPACE}::rcc
                       ARGS --no-compress --binary -o ${rccPath} ${qrcPath}
                       MAIN_DEPENDENCY ${qrcPath}
                       DEPENDS ${fileListAbsConfig} VERBATIM)
endfunction()


function(GenerateQrcWithTranslations resourceFolder translationsRoot)
    set(srcDir ${translationsRoot})
    set(destDir ${CMAKE_BINARY_DIR}/assetsCompiled/${resourceFolder})
    set(qrcName ${CMAKE_BINARY_DIR}/assetsCompiled/${resourceFolder}.qrc)
    set(rccName ${CMAKE_BINARY_DIR}/assetsCompiled/${resourceFolder}.rcc)
    file(MAKE_DIRECTORY "${destDir}")
    set(masks ${srcDir}/*.ts)
    file(GLOB_RECURSE fileListAbsSrc   ${masks})

    set(QRC_PREFIX ${resourceFolder}) # name is important for .in file
    set(QRC_FILES)                    # name is important for .in file

    set(fileListAbsConfig)
    foreach(tsFileAbs ${fileListAbsSrc})
        string(REPLACE "${srcDir}/" "" relFile "${tsFileAbs}")
        string(REPLACE ".ts" ".qm" relFile "${relFile}")
        set(qmFileAbs "${destDir}/${relFile}")
        list(APPEND fileListAbsConfig ${qmFileAbs})

        #configure_file(${absFile} ${destFileAbs} COPYONLY)
        add_custom_command(OUTPUT ${qmFileAbs}
                           COMMAND ${QT_CMAKE_EXPORT_NAMESPACE}::lrelease
                           ARGS ${tsFileAbs} -qm ${qmFileAbs}
                           MAIN_DEPENDENCY ${tsFileAbs} VERBATIM)

        string(REPLACE "${resourceFolder}/" "" file "${relFile}")
        set(QRC_FILES "${QRC_FILES}<file alias=\"${file}\">${resourceFolder}/${relFile}</file>\n")
    endforeach()
    AddQrcOutput(${rccName} ${qrcName} ${fileListAbsConfig})
endfunction()
