import dbus
import dbus.mainloop.glib
import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk

from imutils.video import VideoStream
from pyzbar import pyzbar
import argparse
import datetime
import imutils
import time
# import cv2
from pprint import pprint

# construct the argument parser and parse the arguments
arg_parser = argparse.ArgumentParser()
arg_parser.add_argument('-o', '--output', type=str, default='barcodes.csv',
                        help='path to output CSV file containing barcodes')
arg_parser.add_argument("-s", "--systemdbus", type=bool, default=False,
                        help="use the system bus instead of the session bus")
args = vars(arg_parser.parse_args())

# Initialize the video stream
print('Starting video stream...')
vs = VideoStream(usePiCamera=True).start()
# Allow time for camera to warm up
time.sleep(2.0)

def drive_towards_qr():
    frame = vs.read()
    # Native 3280 × 2464
    # Resize to 1/4 for quicker processing
    image_width_px=int(3280/4)
    image_height_px=int(2464/4)
    frame = imutils.resize(frame, width=image_width_px, height=image_height_px)

    # Find any barcodes in the frame and decode them
    barcodes = pyzbar.decode(frame)

    # loop over the detected barcodes
    for barcode in barcodes:
        # Get the position and size of the QR code bounding box
        (x, y, w, h) = barcode.rect
        
        centre_x = x + (w / 2)
        x_fraction = (centre_x / image_width_px)
        
        print('x_fraction: ' + str(x_fraction))

        # Convert data from bytes to string
        barcodeData = barcode.data.decode("utf-8")
        barcodeType = barcode.type

        focal_length_mm = 3.04
        qr_real_height_mm = 96
        sensor_height_mm = 2.76
        distance_mm = int((focal_length_mm * qr_real_height_mm * image_height_px) / (h * sensor_height_mm))
        distance_cm = int(distance_mm / 10)
        
        print('distance (cm): ' + str(distance_cm))

        max_speed = 500
        target_distance_cm = 20
        # Used to calculate speed.  This is the distance at which the speed should be maximum.
        max_qr_detection_distance= 70
        speed = ((distance_cm - target_distance_cm) * (max_speed / (max_qr_detection_distance - target_distance_cm)))
        left_motor_target = int(speed * (1 - x_fraction))
        right_motor_target = int(speed * x_fraction)
        
        print('left:  ' + str(left_motor_target))
        print('right: ' + str(right_motor_target))
        
        # Use the DBUS network to set the motor target speeds variable on the Thymio-II
        network.SetVariable('thymio-II', 'motor.left.target', [left_motor_target])
        network.SetVariable('thymio-II', 'motor.right.target', [right_motor_target])
        
        return True
    
    # If no QR codes found, set motor speeds to 0
    # This is also useful for stopping the script, because the Thymio-II will maintain the current
    # motor behaviour after the script has stopped running
    network.SetVariable('thymio-II', 'motor.left.target', [0])
    network.SetVariable('thymio-II', 'motor.right.target', [0])
    
    return True


if __name__ == '__main__':
    # Set up the DBUS so the script may communicate with the Thymio-II
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    if args['systemdbus']:
        bus = dbus.SystemBus()
    else:
        bus = dbus.SessionBus()

    # Create Aseba network - make sure the Aseba Medulla service is running
    network = dbus.Interface(bus.get_object('ch.epfl.mobots.Aseba', '/'),
                            dbus_interface='ch.epfl.mobots.AsebaNetwork')

    # Print in the terminal the name of each Aseba Node
    print(network.GetNodesList())

    # GObject loop
    print('starting loop')
    loop = gi.repository.GObject.MainLoop()
    try:
        # Call loop method every 1 millisecond
        handle = gi.repository.GObject.timeout_add(1, drive_towards_qr)
        loop.run()
    except KeyboardInterrupt:
        # When the user presses Ctrl-C, close everything down nicely
        loop.quit()
        loop = None
        # Remove the "C" so when Ctrl-C is pressed, it results in "^Cleaning up..."
        print('leaning up...')
        network.SetVariable('thymio-II', 'motor.left.target', [0])
        network.SetVariable('thymio-II', 'motor.right.target', [0])
        vs.stop()
