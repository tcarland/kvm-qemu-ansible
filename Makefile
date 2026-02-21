# Makefile
#
CP=cp --preserve

all: docs

.PHONY: docs
docs:
	( mkdocs build )

pdf: 
	( cd docs; make all )
	@echo

clean:
	( cd docs; make clean )
	( rm -rf site/ ) || true
	@echo

distclean: clean

install:
ifdef TCAMAKE_PREFIX
	( $(CP) bin/kvm-mgr.sh $(TCAMAKE_PREFIX)/bin )
	( $(CP) bin/kvmsh $(TCAMAKE_PREFIX)/bin )
	( $(CP) bin/vm-consumptions.sh $(TCAMAKE_PREFIX)/bin )
endif
