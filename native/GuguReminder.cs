using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
using Forms = System.Windows.Forms;

[assembly:System.Reflection.AssemblyTitle("咕咕提醒原生版")]
[assembly:System.Reflection.AssemblyProduct("Gugu Reminder Native")]
[assembly:System.Reflection.AssemblyVersion("0.2.0.0")]
[assembly:System.Reflection.AssemblyFileVersion("0.2.0.0")]

namespace GuguNative {
 public sealed class Clock {
  public static readonly string[] Kinds={"water","walk","eyes"};
  public readonly Dictionary<string,int> Intervals=new Dictionary<string,int>();
  public readonly Dictionary<string,double> Next=new Dictionary<string,double>();
  public double PausedUntil;
  readonly string file; Dictionary<string,object> root=new Dictionary<string,object>();
  static readonly JavaScriptSerializer json=new JavaScriptSerializer();
  public static double Now {get{return Math.Floor((DateTime.UtcNow-new DateTime(1970,1,1)).TotalMilliseconds);}}
  static Dictionary<string,object> Map(object value){return value as Dictionary<string,object>??new Dictionary<string,object>();}
  static object Get(Dictionary<string,object> map,string key){object value;return map.TryGetValue(key,out value)?value:null;}
  static double Number(object value,double fallback){try{double n=Convert.ToDouble(value,CultureInfo.InvariantCulture);return value==null||Double.IsNaN(n)||Double.IsInfinity(n)?fallback:n;}catch{return fallback;}}
  public Clock(string filename,string import){
   file=filename;
   try{string source=File.Exists(file)?file:import;if(source!=null&&File.Exists(source))root=Map(json.DeserializeObject(File.ReadAllText(source)));}catch{}
   var state=Map(Get(root,"reminders"));var intervals=Map(Get(state,"intervals"));var next=Map(Get(state,"next"));
   PausedUntil=Number(Get(state,"pausedUntil"),0);int[] defaults={60,50,40};
   for(int i=0;i<Kinds.Length;i++){
    string k=Kinds[i];double n=Number(Get(intervals,k),defaults[i]);Intervals[k]=n>=1&&n<=1440&&n==Math.Floor(n)?(int)n:defaults[i];
    double due=Number(Get(next,k),0);Next[k]=due>Now?due:Math.Max(Now,PausedUntil)+Intervals[k]*60000;
   }
  }
  public string Due(double now){return now<PausedUntil?null:Kinds.OrderBy(k=>Next[k]).FirstOrDefault(k=>Next[k]<=now);}
  public void Finish(string kind,bool later,double now){Next[kind]=now+(later?(kind=="eyes"?5:10):Intervals[kind])*60000;}
  public void Reset(double now){PausedUntil=0;foreach(string k in Kinds)Next[k]=now+Intervals[k]*60000;}
  public void Pause(double now){Reset(now+3600000);PausedUntil=now+3600000;}
  public void SetIntervals(Dictionary<string,int> values,double now){
   foreach(var pair in values)if(!Intervals.ContainsKey(pair.Key)||pair.Value<1||pair.Value>1440)throw new ArgumentException("请输入 1–1440 的整数");
   foreach(var pair in values)if(Intervals[pair.Key]!=pair.Value){Intervals[pair.Key]=pair.Value;Next[pair.Key]=Math.Max(now,PausedUntil)+pair.Value*60000;}
  }
  public void Save(){
   root["reminders"]=new Dictionary<string,object>{{"intervals",Intervals},{"next",Next},{"pausedUntil",PausedUntil}};
   Directory.CreateDirectory(Path.GetDirectoryName(file));File.WriteAllText(file+".tmp",json.Serialize(root));
   if(File.Exists(file))File.Replace(file+".tmp",file,null);else File.Move(file+".tmp",file);
  }
 }

 // 原始 WebM 由随包携带的 FFmpeg/libvpx 解码；不重编码、不缩放、不量化。
 public sealed class Animation : IDisposable {
  readonly string file;Process decoder;Stream output;int current=-1;string error="";
  public readonly int Width=1080,Height=1080,Fps=24,Count=192;public readonly byte[] Pixels=new byte[1080*1080*4];
  public Animation(string filename){file=filename;if(!File.Exists(file))throw new FileNotFoundException("缺少原始视频",file);Start();}
  void Start(){
   var info=new ProcessStartInfo{FileName=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"assets","ffmpeg.exe"),Arguments="-nostdin -hide_banner -loglevel error -threads 2 -c:v libvpx-vp9 -i \""+file+"\" -an -threads 2 -f rawvideo -pix_fmt bgra pipe:1",UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true};
   error="";decoder=new Process{StartInfo=info};decoder.ErrorDataReceived+=(sender,args)=>{if(args.Data!=null&&error.Length<8000)error+=args.Data+Environment.NewLine;};decoder.Start();decoder.BeginErrorReadLine();output=decoder.StandardOutput.BaseStream;current=-1;
  }
  public void Frame(int index){
   index=Math.Max(0,Math.Min(Count-1,index));if(index<current){Stop();Start();}
   while(current<index){int n=0,read;while(n<Pixels.Length&&(read=output.Read(Pixels,n,Pixels.Length-n))>0)n+=read;
    if(n!=Pixels.Length)throw new InvalidDataException("原始透明视频解码失败: "+error);current++;
   }
  }
  void Stop(){if(decoder==null)return;try{if(!decoder.HasExited)decoder.Kill();decoder.WaitForExit(2000);}catch{}output.Dispose();decoder.Dispose();decoder=null;}
  public void Dispose(){Stop();}
 }

 public static class Theme {
  public static readonly Brush Ink=Brush("#593c4c"),Muted=Brush("#8c6375"),Paper=Brush("#fff8fb"),Line=Brush("#f0dce6"),Pink=Brush("#a74570");
  public static readonly FontFamily Cartoon=new FontFamily(new Uri(AppDomain.CurrentDomain.BaseDirectory),"./assets/#ZCOOL KuaiLe");
  public static SolidColorBrush Brush(string hex){return new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));}
  public static TextBlock Text(string text,double size,Brush color,bool cartoon){return new TextBlock{Text=text,FontSize=size,Foreground=color,FontFamily=cartoon?Cartoon:new FontFamily("Microsoft YaHei"),VerticalAlignment=VerticalAlignment.Center,TextWrapping=TextWrapping.Wrap};}
  public static Button Button(string label,Action action,bool primary){
   var b=new Button{Content=label,FontFamily=Cartoon,FontSize=15,Padding=new Thickness(14,8,14,8),Margin=new Thickness(0,0,8,0),Background=primary?Pink:Brush("#fff1f7"),Foreground=primary?Brushes.White:Ink,BorderBrush=Line,BorderThickness=new Thickness(1),Cursor=System.Windows.Input.Cursors.Hand};
   var border=new FrameworkElementFactory(typeof(Border));border.SetValue(Border.CornerRadiusProperty,new CornerRadius(10));border.SetValue(Border.BackgroundProperty,new TemplateBindingExtension(Control.BackgroundProperty));border.SetValue(Border.BorderBrushProperty,new TemplateBindingExtension(Control.BorderBrushProperty));border.SetValue(Border.BorderThicknessProperty,new TemplateBindingExtension(Control.BorderThicknessProperty));
   var content=new FrameworkElementFactory(typeof(ContentPresenter));content.SetValue(FrameworkElement.MarginProperty,new TemplateBindingExtension(Control.PaddingProperty));content.SetValue(FrameworkElement.HorizontalAlignmentProperty,HorizontalAlignment.Center);border.AppendChild(content);b.Template=new ControlTemplate(typeof(Button)){VisualTree=border};
   b.Click+=(s,e)=>action();return b;
  }
 }

 public sealed class SettingsWindow : Window {
  readonly NativeApp owner;readonly TextBlock status,message;readonly Button pause;readonly Dictionary<string,TextBox> inputs=new Dictionary<string,TextBox>();
  public SettingsWindow(NativeApp app){
   owner=app;Title="咕咕提醒 · 原生版";Width=440;SizeToContent=SizeToContent.Height;MaxHeight=SystemParameters.WorkArea.Height-40;ResizeMode=ResizeMode.NoResize;Background=Theme.Paper;WindowStartupLocation=WindowStartupLocation.CenterScreen;
   var body=new StackPanel{Margin=new Thickness(26)};Content=new ScrollViewer{Content=body,VerticalScrollBarVisibility=ScrollBarVisibility.Auto};
   status=Theme.Text("",12,Theme.Muted,false);body.Children.Add(status);
   var heading=Theme.Text("休息一下，元气回来！",25,Theme.Ink,true);heading.Margin=new Thickness(0,18,0,7);body.Children.Add(heading);
   body.Children.Add(Theme.Text("小小提醒，陪你照顾好自己。",14,Theme.Muted,false));
   var grid=new System.Windows.Controls.Primitives.UniformGrid{Columns=3,Margin=new Thickness(0,24,0,18)};body.Children.Add(grid);string[] labels={"喝水","走动","护眼"};string[] icons={"M12,3 C9,7 5,11 5,15 A7,7 0 0 0 19,15 C19,11 15,7 12,3 Z","M7,20 L10,14 L14,16 L16,21 M6,12 L10,7 L14,11 L18,12 M10,7 L12,14 M16,4 A2,2 0 1 1 12,4 A2,2 0 1 1 16,4","M2,12 C6,3 18,3 22,12 C18,21 6,21 2,12 Z M15,12 A3,3 0 1 1 9,12 A3,3 0 1 1 15,12"};
   for(int i=0;i<3;i++){
    string k=Clock.Kinds[i];var stack=new StackPanel{Margin=new Thickness(13,16,13,16)};
    stack.Children.Add(new System.Windows.Shapes.Path{Data=Geometry.Parse(icons[i]),Stroke=Theme.Pink,StrokeThickness=1.6,Width=24,Height=24,Stretch=Stretch.Uniform,HorizontalAlignment=HorizontalAlignment.Left});var label=Theme.Text(labels[i],16,Theme.Ink,true);label.Margin=new Thickness(0,12,0,12);stack.Children.Add(label);
    var input=new TextBox{Text=app.Clock.Intervals[k].ToString(),FontSize=25,Foreground=Theme.Ink,BorderThickness=new Thickness(0),Background=Brushes.Transparent,Padding=new Thickness(0),MaxLength=4};inputs[k]=input;stack.Children.Add(input);
    var unit=Theme.Text("分钟 / 次",12,Theme.Muted,false);unit.Margin=new Thickness(0,12,0,0);stack.Children.Add(unit);
    grid.Children.Add(new Border{Background=Theme.Brush("#fcebf2"),CornerRadius=new CornerRadius(12),Margin=new Thickness(0,0,i==2?0:9,0),Child=stack});
   }
   message=Theme.Text("修改的项目从保存时重新计时",12,Theme.Muted,false);body.Children.Add(message);
   var save=Theme.Button("保存设置",Save,true);save.Margin=new Thickness(0,18,0,22);body.Children.Add(save);
   var actions=new StackPanel{Orientation=Orientation.Horizontal};pause=Theme.Button("暂停 1 小时",()=>app.SetPause(!(app.Clock.PausedUntil>Clock.Now)),false);actions.Children.Add(pause);actions.Children.Add(Theme.Button("退出",()=>app.Shutdown(),false));body.Children.Add(actions);
   Closing+=(s,e)=>{if(!app.Exiting){e.Cancel=true;Hide();}};Refresh();
  }
  void Save(){try{
   var values=new Dictionary<string,int>();foreach(string k in Clock.Kinds){int n;if(!Int32.TryParse(inputs[k].Text,out n)||n<1||n>1440)throw new ArgumentException("请输入 1–1440 的整数");values[k]=n;}
   owner.Clock.SetIntervals(values,Clock.Now);owner.Clock.Save();message.Text="已保存，重启后也会保留";
  }catch(Exception error){message.Text=error.Message;}}
  public void Refresh(){bool paused=owner.Clock.PausedUntil>Clock.Now;status.Text=paused?"● 已暂停 · 1 小时后自动恢复":"● 提醒进行中";pause.Content=paused?"恢复提醒":"暂停 1 小时";}
 }

 public sealed class ReminderWindow : Window {
  readonly NativeApp owner;readonly string kind;readonly Animation animation;readonly Image image;readonly WriteableBitmap bitmap;readonly DispatcherTimer timer;readonly Stopwatch watch=new Stopwatch();
  readonly Button done;readonly TextBlock title,counter;readonly StackPanel group;bool finished;IntPtr handle;int lastFrame=-1;bool ignoring;
  [DllImport("user32.dll")]static extern int GetWindowLong(IntPtr h,int index);
  [DllImport("user32.dll")]static extern int SetWindowLong(IntPtr h,int index,int value);
  [DllImport("user32.dll")]static extern bool GetCursorPos(out NativePoint point);
  [DllImport("user32.dll")]static extern short GetAsyncKeyState(int key);
  [StructLayout(LayoutKind.Sequential)]struct NativePoint{public int X,Y;}
  public ReminderWindow(NativeApp app,string reminder){
   owner=app;kind=reminder;animation=new Animation(Path.Combine(app.Assets,kind+".webm"));
   AllowsTransparency=true;WindowStyle=WindowStyle.None;Background=Brushes.Transparent;ShowInTaskbar=false;Topmost=true;ShowActivated=false;ResizeMode=ResizeMode.NoResize;
   group=new StackPanel{HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center};Content=group;
   bitmap=new WriteableBitmap(animation.Width,animation.Height,96,96,PixelFormats.Bgra32,null);image=new Image{Source=bitmap,Stretch=Stretch.Uniform};group.Children.Add(image);
   var line=new WrapPanel{HorizontalAlignment=HorizontalAlignment.Center,VerticalAlignment=VerticalAlignment.Center};
   string[] words={"咕噜咕噜，喝水啦～","走走呀，舒展一下～","眨眨眼，看向远处～"};title=Theme.Text(words[Array.IndexOf(Clock.Kinds,kind)],19,Theme.Brush("#5d4a35"),true);title.Margin=new Thickness(0,0,9,0);line.Children.Add(title);
   counter=Theme.Text("20 秒",14,Theme.Muted,true);counter.Margin=new Thickness(0,0,8,0);if(kind=="eyes")line.Children.Add(counter);
   done=Theme.Button(kind=="eyes"?"休息中…":kind=="water"?"喝好啦":"这就起来",()=>Finish(false),false);done.Background=Theme.Brush("#e1ebd3");done.Foreground=Theme.Brush("#547044");done.FontSize=14;done.Padding=new Thickness(9,4,9,4);line.Children.Add(done);
   var later=Theme.Button("等一下",()=>Finish(true),false);later.FontSize=14;later.Padding=new Thickness(7,4,7,4);later.Background=Brushes.Transparent;line.Children.Add(later);
   var close=Theme.Button("×",()=>Finish(false,true),false);close.Padding=new Thickness(4);close.Background=Brushes.Transparent;line.Children.Add(close);
   var bubble=new Border{Child=line,HorizontalAlignment=HorizontalAlignment.Center,Padding=new Thickness(12,8,8,8),Background=Theme.Brush("#fffaf0"),CornerRadius=new CornerRadius(18),Margin=new Thickness(0,8,0,0)};bubble.Visibility=Visibility.Hidden;group.Children.Add(bubble);
   image.MouseLeftButtonDown+=(s,e)=>Finish(false);
   SourceInitialized+=(s,e)=>{handle=new WindowInteropHelper(this).Handle;SetWindowLong(handle,-20,GetWindowLong(handle,-20)|0x80000|0x80|0x08000000);Layout();};
   SystemEvents.DisplaySettingsChanged+=DisplayChanged;
   timer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(1000.0/24)};
   timer.Tick+=(s,e)=>{
    try{
     double elapsed=watch.Elapsed.TotalSeconds;int frame=Math.Min(animation.Count-1,(int)(elapsed*animation.Fps));
     if(frame!=lastFrame){animation.Frame(frame);bitmap.WritePixels(new Int32Rect(0,0,animation.Width,animation.Height),animation.Pixels,animation.Width*4,0);lastFrame=frame;}
     if(elapsed>=2.65)bubble.Visibility=Visibility.Visible;
     bool ready=kind!="eyes"||elapsed>=22.65;done.IsEnabled=ready;
     if(kind=="eyes"){counter.Text=ready?"✓":Math.Max(0,(int)Math.Ceiling(22.65-elapsed))+" 秒";if(ready){title.Text="好啦，慢慢回来";done.Content="休息好了";}}
     HitTest();
     if((GetAsyncKeyState(0x1b)&0x8000)!=0)Finish(false,true);
     if(elapsed>=(kind=="eyes"?24.85:9.15))Finish(false,true);
    }catch(Exception error){app.Log(error);Finish(false,true);}
   };
   Closed+=(s,e)=>{timer.Stop();animation.Dispose();SystemEvents.DisplaySettingsChanged-=DisplayChanged;};
   Loaded+=(s,e)=>{watch.Start();timer.Start();};
  }
  void DisplayChanged(object sender,EventArgs args){Dispatcher.BeginInvoke(new Action(Layout));}
  void Layout(){var area=SystemParameters.WorkArea;Left=area.Left;Top=area.Top;Width=area.Width;Height=area.Height;double size=Math.Max(80,Math.Min(900,Math.Min(area.Width-48,area.Height-170)));image.Width=image.Height=size;group.MaxWidth=Math.Max(100,area.Width-48);}
  void HitTest(){
   NativePoint cursor;GetCursorPos(out cursor);Point point=PointFromScreen(new Point(cursor.X,cursor.Y));Point top=image.TranslatePoint(new Point(),this);
   bool hit=false;double x=point.X-top.X,y=point.Y-top.Y;
   if(x>=0&&x<image.ActualWidth&&y>=0&&y<image.ActualHeight){int px=(int)(x/image.ActualWidth*animation.Width),py=(int)(y/image.ActualHeight*animation.Height);hit=animation.Pixels[(py*animation.Width+px)*4+3]>24;}
   var bubble=(Border)group.Children[1];Point b=bubble.TranslatePoint(new Point(),this);hit|=bubble.IsVisible&&point.X>=b.X&&point.X<=b.X+bubble.ActualWidth&&point.Y>=b.Y&&point.Y<=b.Y+bubble.ActualHeight;
   if(ignoring==hit){ignoring=!hit;int style=GetWindowLong(handle,-20);SetWindowLong(handle,-20,ignoring?style|0x20:style&~0x20);}
  }
  public void Finish(bool later,bool force=false){if(finished||(!force&&!later&&kind=="eyes"&&watch.Elapsed.TotalSeconds<22.65))return;finished=true;owner.Clock.Finish(kind,later,Clock.Now);owner.Clock.Save();Close();owner.Reminder=null;}
  public void Dismiss(){if(finished)return;finished=true;Close();owner.Reminder=null;}
 }

 public sealed class NativeApp : Application {
  public Clock Clock;public SettingsWindow Settings;public ReminderWindow Reminder;public bool Exiting;public string Assets;
  Forms.NotifyIcon tray;DispatcherTimer tick;EventWaitHandle signal;Thread signalThread;string stateDir;bool smoke;
  public void Log(Exception error){try{Directory.CreateDirectory(stateDir);File.AppendAllText(Path.Combine(stateDir,"native-error.log"),DateTime.Now+" "+error+Environment.NewLine);}catch{}}
  public void SetPause(bool paused){if(paused){Clock.Pause(Clock.Now);if(Reminder!=null)Reminder.Dismiss();}else Clock.Reset(Clock.Now);Clock.Save();if(Settings!=null)Settings.Refresh();}
  public void OpenSettings(){if(Reminder!=null)Reminder.Finish(false,true);if(Settings==null)Settings=new SettingsWindow(this);Settings.Refresh();Settings.Show();Settings.Activate();}
  protected override void OnStartup(StartupEventArgs e){
   base.OnStartup(e);ShutdownMode=ShutdownMode.OnExplicitShutdown;smoke=e.Args.Contains("--smoke-test");
   Assets=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"assets");stateDir=smoke?Path.Combine(Path.GetTempPath(),"gugu-native-qa-"+Guid.NewGuid().ToString("N")):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"Golden Paw Native");
   try{
    Clock=new Clock(Path.Combine(stateDir,"state.json"),smoke?null:Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"Golden Paw","state.json"));Clock.Save();
    tray=new Forms.NotifyIcon{Icon=new System.Drawing.Icon(Path.Combine(Assets,"gugu.ico")),Text="咕咕提醒 · Windows 原生版",Visible=true};
    var menu=new Forms.ContextMenuStrip();menu.Items.Add("提醒设置",null,(s,a)=>OpenSettings());menu.Items.Add("暂停提醒 1 小时",null,(s,a)=>SetPause(true));menu.Items.Add("恢复提醒",null,(s,a)=>SetPause(false));menu.Items.Add(new Forms.ToolStripSeparator());menu.Items.Add("退出",null,(s,a)=>Shutdown());tray.ContextMenuStrip=menu;tray.MouseClick+=(s,a)=>{if(a.Button==Forms.MouseButtons.Left)OpenSettings();};
    tick=new DispatcherTimer{Interval=TimeSpan.FromSeconds(1)};tick.Tick+=(s,a)=>{
     if(Clock.PausedUntil>0&&Clock.PausedUntil<=GuguNative.Clock.Now){Clock.PausedUntil=0;Clock.Save();if(Settings!=null)Settings.Refresh();}
     if(Reminder!=null||(Settings!=null&&Settings.IsVisible))return;string due=Clock.Due(GuguNative.Clock.Now);if(due!=null){Reminder=new ReminderWindow(this,due);Reminder.Show();}
    };tick.Start();
    SystemEvents.PowerModeChanged+=PowerChanged;
    if(!smoke){signal=new EventWaitHandle(false,EventResetMode.AutoReset,"Local\\GuguReminderNativeOpen");signalThread=new Thread(()=>{while(true){signal.WaitOne();Dispatcher.BeginInvoke(new Action(OpenSettings));}});signalThread.IsBackground=true;signalThread.Start();}
    else SmokeTest();
   }catch(Exception error){Log(error);MessageBox.Show(error.Message,"咕咕提醒启动失败");Shutdown(1);}
  }
  void PowerChanged(object sender,PowerModeChangedEventArgs e){if(e.Mode==PowerModes.Resume)Dispatcher.BeginInvoke(new Action(()=>{Clock.Reset(GuguNative.Clock.Now);Clock.Save();if(Reminder!=null)Reminder.Dismiss();if(Settings!=null)Settings.Refresh();}));}
  protected override void OnExit(ExitEventArgs e){Exiting=true;if(tick!=null)tick.Stop();SystemEvents.PowerModeChanged-=PowerChanged;if(tray!=null){tray.Visible=false;tray.Dispose();}if(Reminder!=null)Reminder.Dismiss();if(Settings!=null)Settings.Close();base.OnExit(e);}
  static void Capture(FrameworkElement element,string file){element.UpdateLayout();var bitmap=new RenderTargetBitmap((int)element.ActualWidth,(int)element.ActualHeight,96,96,PixelFormats.Pbgra32);bitmap.Render(element);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bitmap));using(var output=File.Create(file))encoder.Save(output);}
  void SmokeTest(){
   string output=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"qa");Directory.CreateDirectory(output);OpenSettings();
   var qa=new DispatcherTimer{Interval=TimeSpan.FromSeconds(2)};int step=0;
   qa.Tick+=(s,e)=>{try{
    if(step==0){Capture(Settings,Path.Combine(output,"settings.png"));SetPause(true);if(Clock.PausedUntil<=GuguNative.Clock.Now)throw new Exception("暂停失败");SetPause(false);if(Clock.PausedUntil!=0)throw new Exception("恢复失败");Settings.Hide();Clock.Next["water"]=GuguNative.Clock.Now-1;}
    if(step==3){if(Reminder==null)throw new Exception("到期提醒未显示");Capture(Reminder,Path.Combine(output,"water.png"));}
    if(step==4){if(Reminder!=null)Reminder.Finish(true,true);if(Clock.Next["water"]<GuguNative.Clock.Now+590000)throw new Exception("稍后未重排");File.WriteAllText(Path.Combine(output,"result.txt"),"PASS: 设置窗口、暂停恢复、实际到期动画、透明渲染、稍后重排");qa.Stop();Shutdown();}
    step++;
   }catch(Exception error){File.WriteAllText(Path.Combine(output,"result.txt"),error.ToString());qa.Stop();Shutdown(1);}};qa.Start();
  }
 }

 public static class Program {
  [STAThread]public static int Main(string[] args){
   if(args.Contains("--self-test"))return SelfTest();
   bool created;using(var mutex=new Mutex(true,"Local\\GuguReminderNative",out created)){
    if(!created&&!args.Contains("--smoke-test")){try{EventWaitHandle.OpenExisting("Local\\GuguReminderNativeOpen").Set();}catch{}return 0;}
    return new NativeApp().Run();
   }
  }
  static void Assert(bool value,string message){if(!value)throw new Exception(message);}
  static int SelfTest(){string output=Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"self-test.txt"),temp=Path.Combine(Path.GetTempPath(),"gugu-clock-"+Guid.NewGuid().ToString("N"));try{
   string file=Path.Combine(temp,"state.json");var clock=new Clock(file,null);double now=Clock.Now;
   Assert(clock.Intervals["water"]==60&&clock.Intervals["eyes"]==40,"默认间隔");clock.Next["water"]=now-1;Assert(clock.Due(now)=="water","到期检查");clock.Finish("water",true,now);Assert(clock.Next["water"]==now+600000,"喝水稍后");clock.Finish("eyes",true,now);Assert(clock.Next["eyes"]==now+300000,"护眼稍后");
   clock.Pause(now);Assert(clock.Due(now+1000)==null,"暂停");double keep=clock.Next["walk"];clock.SetIntervals(new Dictionary<string,int>{{"water",30}},now);Assert(clock.Next["water"]==clock.PausedUntil+1800000&&clock.Next["walk"]==keep,"暂停中保存间隔");bool rejected=false;try{clock.SetIntervals(new Dictionary<string,int>{{"water",0}},now);}catch(ArgumentException){rejected=true;}Assert(rejected,"非法设置拒绝");clock.Save();var reloaded=new Clock(file,null);Assert(reloaded.Intervals["water"]==30&&reloaded.PausedUntil==clock.PausedUntil,"存档重载");clock.Reset(now);Assert(clock.PausedUntil==0&&clock.Next["water"]==now+1800000,"恢复");
   string imported=Path.Combine(temp,"legacy.json");File.WriteAllText(imported,"{\"resident\":true,\"reminders\":{\"intervals\":{\"water\":25,\"walk\":45,\"eyes\":35}}}");
   var legacy=new Clock(Path.Combine(temp,"imported.json"),imported);Assert(legacy.Intervals["water"]==25,"旧版设置迁移");legacy.Save();Assert(File.ReadAllText(Path.Combine(temp,"imported.json")).Contains("resident"),"旧存档字段保留");
   var watch=Stopwatch.StartNew();long decoded=0;foreach(string kind in Clock.Kinds)using(var animation=new Animation(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"assets",kind+".webm"))){for(int i=0;i<animation.Count;i++){animation.Frame(i);if(kind=="water")for(int px=3;px<animation.Width*40*4;px+=4)Assert(animation.Pixels[px]<24,"帽顶安全边距");decoded++;}animation.Frame(0);animation.Frame(60);Assert(animation.Pixels.Any(b=>b>0),"视频重新播放");}
   File.WriteAllText(output,"PASS: 提醒计时、暂停恢复、间隔校验、存档重载、旧版迁移、"+decoded+" 帧完整解码、帽顶边距、视频重新播放"+Environment.NewLine+"平均解码: "+(watch.Elapsed.TotalMilliseconds/decoded).ToString("F2")+" ms/frame");Directory.Delete(temp,true);return 0;
  }catch(Exception error){File.WriteAllText(output,error.ToString());return 1;}}
 }
}
