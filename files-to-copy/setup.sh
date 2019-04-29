#!/bin/bash

# Many commands have the parameter “-y” to answer yes to any questions that are asked, such as “xxxMB will
# be used, do you want to continue?”  This allows the script to run with minimal assistance from the user.

# This simply updates the Raspberry Pi’s knowledge of the package repository.  It will now know what
# packages are available and the latest versions.
sudo apt update -y
# This command upgrades any installed packages to the latest version the Raspberry Pi knows about (hence
# updating first).
sudo apt upgrade -y

# These lines create and move into the setup directory to keep the setup process clean without cluttering
# arbitrary folders.
SETUP_DIR=/home/pi/thymio/setup
mkdir -p $SETUP_DIR
cd $SETUP_DIR

#--------------------------------------#
#  Install Aseba Medulla & DBUS Stuff  |
#--------------------------------------#

# Here we check if the Aseba Medulla package is already stored locally.  If not, download it.  The Aseba
# Medulla package allows the Raspberry Pi to communicate with the Thymio using DBUS.
if [ ! -f aseba_1.5.5_armhf.deb ]; then
    echo "Aseba file not found.  Downloading..."
    wget https://www.thymio.org/local--files/en:linuxinstall/aseba_1.5.5_armhf.deb
fi

# Install the Aseba Medulla package.  Because it is installed from a local file, dependencies aren’t
# automatically installed.  To fix this we run the fix broken install command, which then checks which
# dependencies are required and installs them.
sudo dpkg --install aseba_1.5.5_armhf.deb
sudo apt --fix-broken install -y
# Finally, two more packages are installed.  GObject for Python and DBUS for Python.  These are both
# used by the Python scripts that will be talking to the Thymio.
sudo apt install python3-gi -y
sudo apt install python3-dbus -y

# Pip is installed for numpy, pyzbar, and imutils.  Pip is a Python package manager, allowing for easily
# installation of Python libraries.  Pretty Print is generally useful for writing Python code.
wget https://bootstrap.pypa.io/get-pip.py
sudo python3 get-pip.py

sudo pip install pprint

#--------------------------------------#
#            Install OpenCV            #
#--------------------------------------#

# Unlike the other libraries, OpenCV cannot simply be installed from the package manager on the
# Raspberry Pi.  It must be compiled locally before installing.

# Here we install all of the dependencies required for the compilation of OpenCV.

sudo apt install build-essential cmake pkg-config -y # cmake helps configure the build process
sudo apt install libjpeg-dev libtiff-dev libpng-dev -y # IO packages for different image formats
# IO packages for different video formats
sudo apt install libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libxvidcore-dev libx264-dev -y
sudo apt install libatlas-base-dev gfortran -y # Help optimise operations
sudo apt install python3-dev -y # Header files so we can have python bindings

# Here we check if the OpenCV source code is already stored locally.  If not, download it.  Afterwards,
# check if it's already unzipped.  If not, unzip it ready for compilation.
mkdir $SETUP_DIR/opencv
cd $SETUP_DIR/opencv
if [ ! -f opencv.zip ]; then
    wget -O opencv.zip https://github.com/Itseez/opencv/archive/4.0.1.zip
fi
if [ ! -f opencv_contrib.zip ]; then
    wget -O opencv_contrib.zip https://github.com/Itseez/opencv_contrib/archive/4.0.1.zip
fi
if [ ! -d opencv-4.0.1 ]; then
    unzip opencv.zip
fi
if [ ! -d opencv_contrib-4.0.1 ]; then
    unzip opencv_contrib.zip
fi

# Install numpy, a Python library for mathematical operations.  Required for OpenCV installation.
sudo pip install numpy

# The cmake command allows the build process to be configured.  We specify we want to build it for
# Python 3 and have to specify all of the Python information so it can make the Python bindings
# (basically making it so Python can use the library).  All of the `python3 -c "blah blah blah"` lines
# are calling Python to get the locations of of the required Python libraries for OpenCV.
cd $SETUP_DIR/opencv/opencv-4.0.1
mkdir $SETUP_DIR/opencv/opencv-4.0.1/build
cd $SETUP_DIR/opencv/opencv-4.0.1/build
cmake -D CMAKE_BUILD_TYPE=RELEASE \
    -D CMAKE_INSTALL_PREFIX=/usr/local \
    -D BUILD_opencv_python2=OFF \
    -D BUILD_opencv_python3=ON \
    -D PYTHON_INCLUDE_DIR=$(python3 -c "from distutils.sysconfig import get_python_inc; print(get_python_inc())") \
    -D PYTHON_INCLUDE_DIR2=$(python3 -c "from os.path import dirname; from distutils.sysconfig import get_config_h_filename; print(dirname(get_config_h_filename()))") \
    -D PYTHON_LIBRARY=$(python3 -c "from distutils.sysconfig import get_config_var;from os.path import dirname,join ; print(join(dirname(get_config_var('LIBPC')),get_config_var('LDLIBRARY')))") \
    -D PYTHON3_NUMPY_INCLUDE_DIRS=$(python3 -c "import numpy; print(numpy.get_include())") \
    -D PYTHON3_PACKAGES_PATH=$(python3 -c "from distutils.sysconfig import get_python_lib; print(get_python_lib())") \
    -D OPENCV_EXTRA_MODULES_PATH=$SETUP_DIR/opencv/opencv_contrib-4.0.1/modules \
    -D ENABLE_NEON=ON \
    -D ENABLE_VFPV3=ON \
    -D BUILD_TESTS=OFF \
    -D OPENCV_ENABLE_NONFREE=ON \
    -D INSTALL_PYTHON_EXAMPLES=OFF \
    -D BUILD_EXAMPLES=OFF ..

# This is a bash function that changes a value in a config file using sed (stream editor).  The sed
# command opens the specified file, searches for the value to be changed using regex and then
# replaces it with the new value. (technically, it replaces the whole line with key=value)
change_config_value () {
    CONFIG_FILE=$1
    TARGET_KEY=$2
    REPLACEMENT_VALUE=$3
    sudo sed -i "s/\($TARGET_KEY *= *\).*/\1$REPLACEMENT_VALUE/" $CONFIG_FILE
}

# To compile OpenCV faster, we'll be utilising all 4 processor cores.  However, using all of the cores
# requires more RAM than the Raspberry Pi has, so we need to increase the swap size.  The swap size is
# how much storage the Raspberry Pi can use as RAM.  The stop and start commands apply the change in
# swap size.
change_config_value /etc/dphys-swapfile CONF_SWAPSIZE 2048
sudo /etc/init.d/dphys-swapfile stop
sudo /etc/init.d/dphys-swapfile start

# This is the command that actually compiles OpenCV.  The `-j4` specifies all 4 cores of the Raspberry
# Pi's processor should be used.
sudo make -j4

# Now OpenCV is compiled, install it.  `ldconfig` creates the necessary links and cache to the most
# recent shared libraries.
sudo make install
sudo ldconfig


# We will now restore the swap size to its original value.  Using the SD card as RAM means there will
# be lots of read and write operations, which can dramatically reduce its lifespan.
change_config_value /etc/dphys-swapfile CONF_SWAPSIZE 100
sudo /etc/init.d/dphys-swapfile stop
sudo /etc/init.d/dphys-swapfile start


#--------------------------------------#
#   Install Camera and Barcode Stuff   #
#--------------------------------------#

# Install the Python library to allow Python to use the Raspberry Pi camera.
sudo apt install python3-picamera -y
# Install the barcode scanning library.
sudo apt install libzbar0 -y
# Install the Python wrapper for the barcode scanning library.
sudo pip install pyzbar
# Install the image utilities library for use with OpenCV.
sudo pip install imutils