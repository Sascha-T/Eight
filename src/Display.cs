using System;
using static SDL2.SDL;
using System.Drawing;
using System.IO;

namespace Eight {
    public class Display {
        public static IntPtr Window = IntPtr.Zero;
        private static IntPtr _hdRenderer = IntPtr.Zero;
        public static IntPtr Surface = IntPtr.Zero;
        public static IntPtr Renderer = IntPtr.Zero;

        public static bool Dirty = true;

        public static ulong[] TextGrid;
        public static byte[] TextFlags;

        private static int BlinkFlagDelay = 500; // ms
        private static int BlinkFlagLastUpdate = 0;
        public static bool BlinkOn = false;

        public static EBF TextFont;

        public static bool Init() {
            Console.WriteLine("Initializing SDL...");

            SDL_SetHint(SDL_HINT_WINDOWS_DISABLE_THREAD_NAMING, "1");

            if ( SDL_Init(SDL_INIT_EVENTS | SDL_INIT_VIDEO | SDL_INIT_AUDIO) != 0 ) {
                Console.WriteLine("SDL_Init Error: {0}", SDL_GetError());
                SDL_Quit();
                return false;
            }

            ResetScreenSize();
            SDL_SetWindowPosition(Window, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED);

            Console.WriteLine("Creating window...");
            Window = SDL_CreateWindow("Eight " + Eight.Version, SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
                (int)(Eight.RealWidth * Eight.WindowScale),
                (int)(Eight.RealHeight * Eight.WindowScale),
                SDL_WindowFlags.SDL_WINDOW_ALLOW_HIGHDPI);

            if ( Window == IntPtr.Zero ) {
                Console.WriteLine("SDL_CreateWindow Error: {0}", SDL_GetError());
                SDL_Quit();
                return false;
            }

            if ( File.Exists("icon.png") ) {
                var icon = LoadImage("icon.png");
                SDL_SetWindowIcon(Window, icon);
            }


            SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "0");
            SDL_SetRenderDrawBlendMode(_hdRenderer, SDL_BlendMode.SDL_BLENDMODE_NONE);

            Console.WriteLine("Creating renderer...");
            _hdRenderer = SDL_CreateRenderer(Window, -1,
                SDL_RendererFlags.SDL_RENDERER_ACCELERATED);
            if ( _hdRenderer == IntPtr.Zero ) {
                Console.WriteLine("SDL_CreateRenderer Error: {0}", SDL_GetError());
                SDL_Quit();
                return false;
            }

            Console.WriteLine("Loading EBF font...");
            try {
                TextFont = new EBF("Assets/font.ebf");
            } catch ( FileNotFoundException e ) {
                Console.WriteLine("Could not find font.ebf");
                Console.WriteLine(e);
                return false;
            }

            return true;
        }

        public static void CreateScreen() {
            if ( Surface != IntPtr.Zero ) {
                SDL_FreeSurface(Surface);
                Surface = IntPtr.Zero;
            }

            if ( Renderer != IntPtr.Zero ) {
                SDL_DestroyRenderer(Renderer);
                Renderer = IntPtr.Zero;
            }

            Surface = SDL_CreateRGBSurface(0, Eight.RealWidth,
                Eight.RealHeight, 32,
                0xff000000,
                0x00ff0000,
                0x0000ff00,
                0x000000ff);

            if ( Surface == IntPtr.Zero ) {
                Console.WriteLine("SDL_CreateRGBSurface() failed: " + SDL_GetError());
                Eight.Quit();
            }

            Renderer = SDL_CreateSoftwareRenderer(Surface);
            if ( Renderer == IntPtr.Zero ) {
                Console.WriteLine("SDL_CreateSoftwareRender() failed: " + SDL_GetError());
                Eight.Quit();
            }

            TextGrid = new ulong[Eight.WindowWidth * Eight.WindowHeight];
            TextFlags = new byte[Eight.WindowWidth * Eight.WindowHeight];

            Dirty = true;
        }

        private static void UpdateScreen() {
            SDL_SetWindowSize(Window,
                (int)(Eight.RealWidth * Eight.WindowScale),
                (int)(Eight.RealHeight * Eight.WindowScale)
            );

            CreateScreen();
        }


        public static void SetScreenSize(int width, int height, float scale) {
            Eight.WindowWidth = width;
            Eight.WindowHeight = height;
            Eight.WindowScale = scale;

            UpdateScreen();
        }

        public static void ResetScreenSize() {
            SetScreenSize(Eight.DefaultWidth, Eight.DefaultHeight, Eight.DefaultScale);
        }

        public static void RenderScreen() {
            if ( !Dirty ) return;

            var sTexture = SDL_CreateTextureFromSurface(_hdRenderer, Surface);
            SDL_RenderClear(_hdRenderer);
            SDL_RenderCopy(_hdRenderer, sTexture, IntPtr.Zero, IntPtr.Zero);
            SDL_RenderPresent(_hdRenderer);
            SDL_DestroyTexture(sTexture);
            Dirty = false;
        }

        public static void Update() {
            if ( BlinkFlagLastUpdate >= BlinkFlagDelay ) {
                for ( int i = 0; i < TextFlags.Length; i++ ) {
                    var flags = (Utils.TextFlag)TextFlags[i];
                    if ( flags.HasFlag(Utils.TextFlag.Blinking) ) {
                        Module.ScreenText.RedrawChar(i);
                    }
                }
                BlinkOn = !BlinkOn;
                BlinkFlagLastUpdate = 0;
            }

            BlinkFlagLastUpdate += Eight.Ticktime;
        }

        public static void Quit() {
            if ( Surface != IntPtr.Zero )
                SDL_FreeSurface(Surface);

            SDL_DestroyRenderer(_hdRenderer);
            SDL_DestroyWindow(Window);
            SDL_Quit();
        }

        public static IntPtr BitmapToSurface(Bitmap bmp) {
            var r = new Rectangle(0, 0, bmp.Width, bmp.Height);
            var cvt = bmp.Clone(r, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            bmp.Dispose();
            var dat = cvt.LockBits(r, System.Drawing.Imaging.ImageLockMode.ReadOnly, cvt.PixelFormat);
            var w = dat.Width;
            var h = dat.Height;
            var stride = dat.Stride;
            IntPtr surface = SDL_CreateRGBSurfaceWithFormat(0, w, h, 32, SDL_PIXELFORMAT_ARGB8888);
            unsafe { // hic sunt dracones
                var s = (SDL_Surface*)surface;
                var pitch = s->pitch;
                var dst = (byte*)s->pixels;
                var src = (byte*)dat.Scan0;
                for ( int y = 0; y < h; y++ ) {
                    Buffer.MemoryCopy(src, dst, w * 4, w * 4);
                    src += stride;
                    dst += pitch;
                }
            }
            cvt.UnlockBits(dat);
            cvt.Dispose();
            return surface;
        }

        public static IntPtr LoadImage(string path) {
            return BitmapToSurface(new(path));
        }

        public static bool Reset() {
            ResetScreenSize();
            SDL_SetWindowTitle(Window, "Eight " + Eight.Version);
            return true;
        }

    }
}