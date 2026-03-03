#!/usr/bin/python3
'''
communicate visually with another computer using QR codes

QR codes sent and received start with a hash of the chunk
last received; the remainder is the chunk being sent
'''
# pylint: disable=c-extension-no-member  # for cv2
import sys, os, json, logging, posixpath, random  # pylint: disable=multiple-imports
# Windows should be able to handle posixpath, and we need it for URLs
from datetime import datetime
from hashlib import sha256
from tkinter import Tk, Label
from fountain import LTEncoder, LTDecoder, xor_bytes
import zlib
import time
try:
    import cv2
except ImportError:
    pass  # not available on iSH
import zmq, base64  # pylint: disable=multiple-imports
from pyzbar.pyzbar import decode, ZBarSymbol
from PIL import Image
from PIL.ImageTk import PhotoImage as Photo
from monkeypatch import qrcode

logging.basicConfig(level=logging.DEBUG if __debug__ else logging.INFO)

HASH = sha256
HASHLENGTH = len(HASH(b'').digest())
EMPTY_HASH = bytes(HASHLENGTH)
CHUNKSIZE = 256
SERIAL_BITS = 32
SERIAL_BYTES = SERIAL_BITS // 8
SERIAL_MODULUS = 1 << SERIAL_BITS
PIPE = posixpath.join(posixpath.abspath(os.curdir), 'command.pipe')
URL = 'ipc://' + PIPE

# Protocol Constants
VERSION = 2
DEFAULT_FPS = 30
DEFAULT_BLOCK_SIZE = 512

logging.info('IPC pipe: %s, url: %s', PIPE, URL)

def transceive():
    '''
    listen on local socket for files to transmit, and watch for incoming
    barcodes from peer
    '''
    capture = cv2.VideoCapture(0)
    window = Tk()
    window.geometry('+0+0')
    label = Label(window, text='Transceiving...')
    label.pack()
    window.update()
    seen = lastseen = b''
    try:
        context = zmq.Context()
        socket = context.socket(zmq.REP)
        socket.bind(URL)
        while capture.isOpened():
            captured = capture.read()
            if captured[0]:
                cv2.imshow('frame captured', captured[1])
                # cv2.moveWindow('frame captured', 1000, 0)
                seen = qrdecode(Image.fromarray(captured[1]))
                if seen != lastseen:
                    logging.debug('seen: %r', seen)
                    lastseen = seen
            if cv2.waitKey(1) & 0xff == ord('q'):
                break
    finally:
        socket.close()
        context.term()
        if posixpath.exists(PIPE):
            os.remove(PIPE)
        capture.release()
        cv2.destroyAllWindows()
        window.destroy()

def transmit(document, fps=DEFAULT_FPS):
    '''
    send document to peer using fountain-encoded animated QRs
    '''
    if not os.path.exists(document):
        logging.error('File not found: %s', document)
        return

    file_size = os.path.getsize(document)
    with open(document, 'rb') as f:
        data = f.read()

    encoder = LTEncoder(data, DEFAULT_BLOCK_SIZE)
    session_id = random.randint(0, SERIAL_MODULUS - 1)
    
    window = Tk()
    window.title(f"Transmitting: {os.path.basename(document)}")
    
    status_text = f"File: {os.path.basename(document)}\nBlocks (K): {encoder.K}\nSymbol ID: 0"
    label = Label(window, text=status_text, font=("Courier", 12), justify="left", padx=20, pady=20)
    label.pack()

    frame_delay = 1.0 / fps
    symbol_id = 0
    
    logging.info("Starting fountain-encoded stream. Session: %d, Blocks: %d", session_id, encoder.K)

    try:
        while True:
            start_time = time.time()
            
            # Generate a new symbol
            seed = random.getrandbits(32)
            degree, symbol_data = encoder.generate_symbol(seed)
            
            # Construct frame: Version(1), Session(4), SymbolID(4), Degree(4), Seed(4), FileSize(8), Payload(N), CRC(4)
            # Total Header: 1 + 4 + 4 + 4 + 4 + 8 = 25 bytes
            header = (
                VERSION.to_bytes(1, 'big') +
                session_id.to_bytes(4, 'big') +
                symbol_id.to_bytes(4, 'big') +
                degree.to_bytes(4, 'big') +
                seed.to_bytes(4, 'big') +
                file_size.to_bytes(8, 'big')
            )
            
            frame_payload = header + symbol_data
            crc = zlib.crc32(frame_payload) & 0xffffffff
            full_frame = frame_payload + crc.to_bytes(4, 'big')
            
            qrshow(label, full_frame)
            
            symbol_id = (symbol_id + 1) % SERIAL_MODULUS
            
            # Update UI metadata
            label.config(text=f"File: {os.path.basename(document)}\nBlocks (K): {encoder.K}\nSymbol ID: {symbol_id}")
            
            elapsed = time.time() - start_time
            sleep_time = max(0, frame_delay - elapsed)
            time.sleep(sleep_time)
            
            window.update()
    except Exception as e:
        logging.error("Transmission stopped: %s", e)
    finally:
        window.destroy()

def receive():
    '''
    receive document from peer using fountain-encoded animated QRs
    '''
    capture = cv2.VideoCapture(0)
    window = Tk()
    window.title("Receiving...")
    
    status_var = json.dumps({"FPS": 0, "Symbols": 0, "Progress": "0%", "Solvable": "No"})
    label = Label(window, text=status_var, font=("Courier", 12), justify="left")
    label.pack(padx=20, pady=20)
    window.update()

    decoder = None
    session_id = None
    file_size = None
    
    start_time = time.time()
    frames_count = 0
    fps = 0
    symbols_received = 0
    
    logging.info("Waiting for fountain-encoded stream...")

    try:
        while capture.isOpened():
            captured = capture.read()
            if not captured[0]:
                continue
            
            frames_count += 1
            now = time.time()
            if now - start_time >= 1.0:
                fps = frames_count / (now - start_time)
                frames_count = 0
                start_time = now
            
            cv2.imshow('Receiver Capture (Press Q to quit)', captured[1])
            
            # Real-time QR decoding
            data = qrdecode(captured[1])
            if data:
                # Header: Version(1), Session(4), SymbolID(4), Degree(4), Seed(4), FileSize(8) = 25 bytes
                # Minimum data size: 25 + 4 (CRC) = 29 bytes
                if len(data) < 29:
                    continue
                
                # Verify CRC
                payload_with_header = data[:-4]
                received_crc = int.from_bytes(data[-4:], 'big')
                if zlib.crc32(payload_with_header) & 0xffffffff != received_crc:
                    logging.warning("CRC mismatch, dropping frame")
                    continue
                
                version = data[0]
                if version != VERSION:
                    logging.warning("Unsupported protocol version: %d", version)
                    continue
                
                curr_session = int.from_bytes(data[1:5], 'big')
                curr_symbol_id = int.from_bytes(data[5:9], 'big')
                curr_degree = int.from_bytes(data[9:13], 'big')
                curr_seed = int.from_bytes(data[13:17], 'big')
                curr_file_size = int.from_bytes(data[17:25], 'big')
                symbol_payload = data[25:-4]
                
                # Initialize decoder on first valid frame of a session
                if session_id != curr_session:
                    logging.info("New session detected: %d, Size: %d", curr_session, curr_file_size)
                    session_id = curr_session
                    file_size = curr_file_size
                    K = math.ceil(file_size / DEFAULT_BLOCK_SIZE)
                    decoder = LTDecoder(K, DEFAULT_BLOCK_SIZE)
                    symbols_received = 0
                
                if not decoder.is_done():
                    old_recovered = decoder.num_recovered
                    decoder.add_symbol(curr_seed, symbol_payload)
                    symbols_received += 1
                    
                    if decoder.num_recovered > old_recovered:
                        logging.debug("Recovered block %d/%d", decoder.num_recovered, decoder.K)

                # Update UI stats
                progress = (decoder.num_recovered / decoder.K) * 100
                stats = {
                    "FPS": f"{fps:.1f}",
                    "Symbols": symbols_received,
                    "Recovered": f"{decoder.num_recovered}/{decoder.K}",
                    "Progress": f"{progress:.1f}%",
                    "Solvable": "Yes" if decoder.is_done() else "No"
                }
                label.config(text="\n".join([f"{k}: {v}" for k, v in stats.items()]))
                window.update()

                if decoder.is_done():
                    logging.info("Reconstruction complete!")
                    final_data = decoder.reconstruct()[:file_size]
                    
                    out_path = os.path.join('received', f"file_{session_id}")
                    os.makedirs('received', exist_ok=True)
                    with open(out_path, 'wb') as f:
                        f.write(final_data)
                    
                    logging.info("Saved to %s", out_path)
                    # We might want to continue or stop. Requirement says loop sender, receiver might stop.
                    # Let's show success and wait for user to quit.
                    label.config(text=f"DONE! Saved to: {out_path}\n" + label.cget("text"))
                    window.update()
                    # To follow requirements of high speed, let's not break immediately, 
                    # but we are done with this file.
            
            if cv2.waitKey(1) & 0xff == ord('q'):
                break
    finally:
        capture.release()
        cv2.destroyAllWindows()
        window.destroy()

def qrshow(label, data):
    '''
    display a QR code
    '''
    if data:
        try:
            image = qrcode.make(base64.b64encode(data))
        except ValueError:
            logging.error('cannot make %r into barcode', data)
            raise
        logging.debug('image type: %s', type(image))
        photo = Photo(image)
        label.configure(image=photo, data=None)
        label.image = photo  # claude: necessary to thwart garbage collection
        label.update()
        logging.debug('image: %s', image)
        code = qrdecode(image)
        logging.debug('code: %r', code)

def qrdecode(image):
    r'''
    get data from QR code image

    >>> testdata = bytes(range(256))
    >>> qr_image = qrcode.make(base64.b64encode(testdata))
    >>> qrdecode(qr_image) == testdata
    True

    the following is from an error while transmitting /bin/bash

    >>> testdata = b'\x00\x00\x02\xef\x07\x00\x00\x00\xde\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\xb0>\x13\x00\x00\x00\x00\x00\x07\x00\x00\x00\
    ... \xdf\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xb8>\x13\x00\x00\x00\
    ... \x00\x00\x07\x00\x00\x00\xe0\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\xc0>\x13\x00\x00\x00\x00\x00\x07\x00\x00\x00\xe1\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\x00\xc8>\x13\x00\x00\x00\x00\x00\x07\x00\x00\
    ... \x00\xe2\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\
    ... \x00\x00\x00\x00'
    >>> len(testdata)  # should be 256 + 4-byte serial number prefix
    260
    >>> qr_image = qrcode.make(base64.b64encode(testdata))
    >>> qrdecode(qr_image) == testdata
    True
    '''
    try:
        pil = image.convert('L')  # to grayscale
    except AttributeError:  # cv2 frame is numpy array
        pil = Image.fromarray(image).convert('L')
    
    decoded = decode(pil, symbols=[ZBarSymbol.QRCODE])
    if decoded:
        try:
            return base64.b64decode(decoded[0].data)
        except base64.binascii.Error:
            pass
    return b''

def chunkhash(data):
    '''
    return binary hash of data
    '''
    return HASH(data).digest()

def test_simulation(filename, loss_rate=0.3):
    '''
    simulate transmission and reception with random frame loss
    '''
    loss_rate = float(loss_rate)
    logging.info("Starting simulation test on %s with %.1f%% loss", filename, loss_rate * 100)
    
    if not os.path.exists(filename):
        logging.error("File not found: %s", filename)
        return

    with open(filename, 'rb') as f:
        original_data = f.read()
    
    file_size = len(original_data)
    encoder = LTEncoder(original_data, DEFAULT_BLOCK_SIZE)
    K = encoder.K
    decoder = LTDecoder(K, DEFAULT_BLOCK_SIZE)
    
    session_id = 999
    symbols_sent = 0
    symbols_received = 0
    
    while not decoder.is_done():
        symbols_sent += 1
        # Randomly drop frame
        if random.random() < loss_rate:
            continue
            
        seed = random.getrandbits(32)
        degree, symbol_data = encoder.generate_symbol(seed)
        
        # Simulate frame construction and decoding (minimal)
        header = (
            VERSION.to_bytes(1, 'big') +
            session_id.to_bytes(4, 'big') +
            symbols_sent.to_bytes(4, 'big') +
            degree.to_bytes(4, 'big') +
            seed.to_bytes(4, 'big') +
            file_size.to_bytes(8, 'big')
        )
        frame_payload = header + symbol_data
        crc = zlib.crc32(frame_payload) & 0xffffffff
        full_frame = frame_payload + crc.to_bytes(4, 'big')
        
        # Receiver side
        received_crc = int.from_bytes(full_frame[-4:], 'big')
        if zlib.crc32(full_frame[:-4]) & 0xffffffff == received_crc:
            decoder.add_symbol(seed, symbol_data)
            symbols_received += 1
            
        if symbols_sent % 50 == 0:
            logging.info("Sent: %d, Received: %d, Recovered: %d/%d", 
                         symbols_sent, symbols_received, decoder.num_recovered, K)

    reconstructed = decoder.reconstruct()[:file_size]
    if reconstructed == original_data:
        logging.info("SUCCESS! Reconstructed %d bytes with %.1f%% loss", file_size, loss_rate * 100)
        logging.info("Total frames sent: %d (Overhead vs K: %.1f%%)", symbols_sent, (symbols_sent / K - 1) * 100)
    else:
        logging.error("FAILURE! Data mismatch")

if __name__ == '__main__':
    callables = [
        (key, value) for key, value in locals().items() if callable(value)
    ]
    logging.debug('callables: %s', callables)
    if len(sys.argv) < 2:
        logging.error('Must specify command and optional args')
    elif sys.argv[1] not in ('transmit', 'receive', 'transceive', 'test_simulation'):
        logging.error('%r not a recognized command', sys.argv[1])
    else:
        eval(sys.argv[1])(*sys.argv[2:])  # pylint: disable=eval-used
