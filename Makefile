APP_NAME=NoteLight

.PHONY: build run clean

build:
	swift build

run:
	swift run $(APP_NAME)

clean:
	rm -rf .build
