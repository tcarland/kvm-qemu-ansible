# Makefile
#
CP=cp --preserve

all: docs

pdf: docs

.PHONY: docs
docs:
	( cd docs; make all )
	@echo

clean:
	( cd docs; make clean )
	@echo

distclean: clean

install:
ifdef $(TCAMAKE_PREFIX)
	( $(CP) bin/kvm-mgr.sh $(TCAMAKE_PREFIX)/bin )
	( $(CP) bin/kvmsh $(TCAMAKE_PREFIX)/bin )
	( $(CP) bin/vm-consumptions.sh $(TCAMAKE_PREFIX)/bin )
endif
