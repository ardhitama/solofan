CC = clang
CFLAGS = -Wall -O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -framework IOKit -framework CoreFoundation
TARGET = smc-helper

all: $(TARGET)

$(TARGET): smc.c smc.h
	$(CC) $(CFLAGS) -o $(TARGET) smc.c

clean:
	rm -f $(TARGET)

# `make` builds smc-helper here for local testing only; the app bundles the
# copy built by the Xcode "Build smc-helper" phase.
.PHONY: all clean
