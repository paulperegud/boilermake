# Note: Parameterized "functions" in this makefile that are marked with
#       "USE WITH EVAL" are only useful in conjuction with eval. This is because
#       those functions result in a block of Makefile syntax that must be
#       evaluated after expansion.
#
#       Since they must be used with eval, most instances of "$" within them
#       need to be escaped with a second "$" to accomodate the double expansion
#       that occurs when eval is invoked. Consequently, attempting to call these
#       "functions" without also using eval will probably not yield the expected
#       result.

# ADD_OBJECT_RULE - Parameterized "function" that adds a pattern rule, using
#   the commands from the second argument, for building object files from source
#   files with the filename extension specified in the first argument.
#
#   USE WITH EVAL
#
define ADD_OBJECT_RULE
$${BUILD_DIR}/%.o: ${1}
	${2}
endef

# ADD_TARGET - Parameterized "function" that adds a new target to the Makefile.
#   The target may be an executable or a library. The two allowable types of
#   targets are distinguished based on the name: library targets must end with
#   the traditional ".a" extension.
#
#   USE WITH EVAL
#
define ADD_TARGET
    ifeq "$$(strip $$(patsubst %.a,%,${1}))" "${1}"
        # Create a new target for linking an executable.
        ${1}: $${${1}_OBJS} $${${1}_PREREQS}
	    @mkdir -p $$(dir $$@)
	    $${LNK} -o ${1} $${TGT_LDFLAGS} $${LDFLAGS} $${${1}_OBJS} \
	        $${TGT_LDLIBS}
    else
        # Create a new target for creating a library archive.
        ${1}: $${${1}_OBJS}
	    @mkdir -p $$(dir $$@)
	    $${AR} r ${1} $${${1}_OBJS}
    endif
endef

# COMPILE_C_CMDS - Commands for compiling C source code.
define COMPILE_C_CMDS
	@mkdir -p $(dir $@)
	${CC} -o $@ -c -MD ${TGT_CFLAGS} ${CFLAGS} ${INCDIRS} ${TGT_INCS} \
	    ${DEFS} ${TGT_DEFS} $<
	@cp ${BUILD_DIR}/$*.d ${BUILD_DIR}/$*.P; \
	 sed -e 's/#.*//' -e 's/^[^:]*: *//' -e 's/ *\\$$//' \
	     -e '/^$$/ d' -e 's/$$/ :/' < ${BUILD_DIR}/$*.d \
	     >> ${BUILD_DIR}/$*.P; \
	 rm -f ${BUILD_DIR}/$*.d
endef

# COMPILE_CXX_CMDS - Commands for compiling C++ source code.
define COMPILE_CXX_CMDS
	@mkdir -p $(dir $@)
	${CXX} -o $@ -c -MD ${TGT_CXXFLAGS} ${CXXFLAGS} ${INCDIRS} \
	    ${TGT_INCS} ${DEFS} ${TGT_DEFS} $<
	@cp ${BUILD_DIR}/$*.d ${BUILD_DIR}/$*.P; \
	 sed -e 's/#.*//' -e 's/^[^:]*: *//' -e 's/ *\\$$//' \
	     -e '/^$$/ d' -e 's/$$/ :/' < ${BUILD_DIR}/$*.d \
	     >> ${BUILD_DIR}/$*.P; \
	 rm -f ${BUILD_DIR}/$*.d
endef

# INCLUDE_MODULE - Parameterized "function" that includes a new module into the
#   makefile. It also recursively includes all submodules of the specified
#   module.
#
#   USE WITH EVAL
#
define INCLUDE_MODULE
    # Initialize module-specific variables, then include the module's file.
    LIBS :=
    MOD_CFLAGS :=
    MOD_CXXFLAGS :=
    MOD_DEFS :=
    MOD_INCDIRS :=
    OBJS :=
    PREREQS :=
    SRCS :=
    SUBMODULES :=
    TARGET :=
    include ${1}

    # Ensure that valid values are set for BUILD_DIR and TARGET_DIR.
    ifeq "$$(strip $${BUILD_DIR})" ""
        BUILD_DIR := build
    endif
    ifeq "$$(strip $${TARGET_DIR})" ""
        TARGET_DIR := .
    endif

    # A directory stack is maintained so that the correct paths are used as we
    # recursively include all submodules. Get the module's directory and push
    # it onto the stack.
    DIR := $(patsubst ./%,%,$(dir ${1}))
    DIR_STACK := $$(call PUSH,$${DIR_STACK},$${DIR})
    OUT_DIR := $${BUILD_DIR}/$${DIR}

    # Determine which target this module's values apply to. A stack is used to
    # keep track of which target is the "current" target as we recursively
    # include other modules.
    ifneq "$$(strip $${TARGET})" ""
        # This module defined a new target. Values defined by this module
        # apply to this new target.
        TGT := $$(strip $${TARGET_DIR}/$${TARGET})
        ALL_TGTS += $${TGT}
        $${TGT}_OBJS :=
        $${TGT}_PREREQS :=
        $${TGT}: TGT_LDLIBS :=
    else
        # The values defined by this module apply to the the "current" target
        # as determined by which target is at the top of the stack.
        TGT := $$(strip $$(call PEEK,$${TGT_STACK}))
    endif

    # Push the current target onto the target stack.
    TGT_STACK := $$(call PUSH,$${TGT_STACK},$${TGT})

    ifneq "$$(strip $${SRCS})" ""
        # This module builds one or more objects from source. Validate the
        # specified sources against the supported source file types.
        BAD_SRCS := $$(strip $$(filter-out $${ALL_SRC_EXTS},$${SRCS}))
        ifneq "$${BAD_SRCS}" ""
            $$(error Unsupported source file(s) in module ${1} [$${BAD_SRCS}])
        endif
        ALL_SRCS += $${SRCS}

        # Convert the source file names to their corresponding object file
        # names.
        OBJS := $${SRCS}
        $$(foreach EXT,$${ALL_SRC_EXTS},$$(eval OBJS := $${OBJS:$${EXT}=%.o}))

        # Add the objects to the current target's list of objects, and create
        # target-specific variables for the objects based on any module-specific
        # flags that were defined.
        OBJS := $$(patsubst %,$${OUT_DIR}%,$${OBJS})
        ALL_OBJS += $${OBJS}
        $${TGT}_OBJS += $${OBJS}
        $${OBJS}: TGT_CFLAGS := $${MOD_CFLAGS}
        $${OBJS}: TGT_CXXFLAGS := $${MOD_CXXFLAGS}
        $${OBJS}: TGT_DEFS := $$(patsubst %,-D%,$${MOD_DEFS})
        $${OBJS}: TGT_INCS := $$(patsubst %,-I%,$${MOD_INCDIRS})
    endif

    ifneq "$$(strip $${LIBS})" ""
        # This module wants to link the target with one or more outside
        # libraries. Add a target-specific variable for setting the required
        # linker directive(s).
        $${LIBS} := $$(patsubst lib%.a,%,$${LIBS})
        $${TGT}: TGT_LDLIBS += $$(patsubst %,-l%,$${LIBS})
    endif

    ifneq "$$(strip $${PREREQS})" ""
        # This module declares that one or more targets are prerequesites of the
        # the current target. Add the other targets to the current target's
        # prerequesite list and add target-specific variables for setting the
        # required linker directive if one of the prerequesites is a library.
        $${TGT}_PREREQS += $$(patsubst %,$${TARGET_DIR}/%,$${PREREQS})
        ifneq "$$(strip $$(filter %.a,$${PREREQS}))" ""
            $${TGT}: TGT_LDFLAGS := $$(patsubst %,-L%,$${TARGET_DIR})
        endif
    endif

    ifneq "$$(strip $${SUBMODULES})" ""
        # This module has submodules. Recursively include them.
        $$(foreach MOD,$${SUBMODULES}, \
            $$(eval $$(call INCLUDE_MODULE,$${DIR}$${MOD})))
    endif

    # Reset the "current" target to it's previous value.
    TGT_STACK := $$(call POP,$${TGT_STACK})
    TGT := $$(call PEEK,$${TGT_STACK})

    # Reset the "current" directory to it's previous value.
    DIR_STACK := $$(call POP,$${DIR_STACK})
    DIR := $$(call PEEK,$${DIR_STACK})
    OUT_DIR := $${BUILD_DIR}/$${DIR}
endef

# PEEK - Parameterized "function" that results in the value at the top of the
#   specified colon-delimited stack.
define PEEK
$(lastword $(subst :, ,${1}))
endef

# POP - Parameterized "function" that pops the top value off of the specified
#   colon-delimited stack, and results in the new value of the stack. Note that
#   the popped value cannot be obtained using this function; use peek for that.
define POP
$(patsubst %:$(lastword $(subst :, ,${1})),%,${1})
endef

# PUSH - Parameterized "function" that pushes a value onto the specified colon-
#   delimited stack, and results in the new value of the stack.
define PUSH
$(patsubst %,${1}:%,${2})
endef

###############################################################################
#
# Start of Makefile Evaluation
#
###############################################################################

# Define the source file extensions that we know how to handle.
C_SRC_EXTS := %.c
CXX_SRC_EXTS := %.C %.cc %.cp %.cpp %.CPP %.cxx %.c++
ALL_SRC_EXTS := ${C_SRC_EXTS} ${CXX_SRC_EXTS}

# Initialize global variables.
ALL_DEPS :=
ALL_OBJS :=
ALL_SRCS :=
ALL_TGTS :=
DEFS :=
DIR_STACK :=
INCDIRS :=
LNK :=
TGT_STACK :=

# Include the main user-supplied module. This also recursively includes all
# user-supplied submodules.
$(eval $(call INCLUDE_MODULE,main.mk))

# Perform post-processing on global variables as needed.
ALL_DEPS := $(patsubst %.o,%.P,${ALL_OBJS})
DEFS := $(patsubst %,-D%,${DEFS})
INCDIRS := $(patsubst %,-I%,${INCDIRS})

ifeq "$(strip ${LNK})" ""
    # Determine whether to use the C or C++ compiler as the front-end to the
    # linker. If there are any C++ sources, use the C++ compiler.
    ifneq "$(strip $(filter ${CXX_SRC_EXTS},${ALL_SRCS}))" ""
        LNK := ${CXX}
    else
        LNK := ${CC}
    endif
endif

# Define "all", which simply builds all user-defined targets, as default goal.
.PHONY: all
all: ${ALL_TGTS}

# Add a new target rule for each user-defined target.
$(foreach TGT,${ALL_TGTS},$(eval $(call ADD_TARGET,${TGT})))

# Add pattern rule(s) for creating compiled object code from C source.
$(foreach EXT,${C_SRC_EXTS},\
  $(eval $(call ADD_OBJECT_RULE,${EXT},$${COMPILE_C_CMDS})))

# Add pattern rule(s) for creating compiled object code from C++ source.
$(foreach EXT,${CXX_SRC_EXTS},\
  $(eval $(call ADD_OBJECT_RULE,${EXT},$${COMPILE_CXX_CMDS})))

# Include generated rules that define additional (header) dependencies.
-include ${ALL_DEPS}

# Define "clean" target to remove all build-generated files.
.PHONY: clean
clean:
	rm -f ${ALL_TGTS} ${ALL_OBJS} ${ALL_DEPS}
