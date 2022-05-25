.PHONY: all deploy test
all: deploy
deploy:
	hugo && firebase deploy
test:
	hugo && firebase hosting\:channel\:deploy quickTest