package com.yavqo.saturn;

import android.app.*;
import android.os.*;
import android.content.*;
import android.graphics.Color;
import android.net.Uri;
import android.view.*;
import android.view.inputmethod.*;
import android.webkit.*;
import android.widget.*;
import org.json.*;
import java.util.*;

public class MainActivity extends Activity {
    private final ArrayList<WebView> tabs = new ArrayList<>();
    private int selected;
    private LinearLayout root;
    private FrameLayout pages;
    private EditText address;
    private Button tabButton, backButton, forwardButton, reloadButton;
    private ProgressBar progress;
    private android.content.SharedPreferences prefs;
    private static final String HOME = "https://mars.yavqo.com";

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        prefs = getSharedPreferences("browser", MODE_PRIVATE);
        root = new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL); root.setBackgroundColor(Color.WHITE);
        root.setOnApplyWindowInsetsListener((v, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars());
                android.graphics.Insets keyboard = insets.getInsets(WindowInsets.Type.ime());
                v.setPadding(bars.left, bars.top, bars.right, Math.max(bars.bottom,keyboard.bottom));
            } else { v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom()); }
            return insets;
        });
        setContentView(root);
        getWindow().setStatusBarColor(BrowserUi.SURFACE);
        getWindow().setNavigationBarColor(BrowserUi.SURFACE);
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        root.setBackgroundColor(BrowserUi.SURFACE);
        LinearLayout header = row(); header.setPadding(dp(20),0,dp(8),0);
        TextView brand = BrowserUi.text(this,"Saturn",20,BrowserUi.INK,true);
        brand.setLetterSpacing(-0.035f); brand.setGravity(Gravity.CENTER_VERTICAL);
        header.addView(brand,new LinearLayout.LayoutParams(0,dp(48),1));
        button(header,"settings",v -> showSettings()).setContentDescription("Open settings");
        progress = new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal);
        progress.setMax(100); progress.setProgressTintList(android.content.res.ColorStateList.valueOf(BrowserUi.INK));
        root.addView(progress,new LinearLayout.LayoutParams(-1,dp(2)));
        pages = new FrameLayout(this); pages.setBackgroundColor(Color.WHITE);
        root.addView(pages,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout bottom = new LinearLayout(this); bottom.setOrientation(LinearLayout.VERTICAL);
        bottom.setPadding(dp(12),dp(10),dp(12),dp(4)); root.addView(bottom,new LinearLayout.LayoutParams(-1,-2));
        LinearLayout navigation = new LinearLayout(this); navigation.setGravity(Gravity.CENTER_VERTICAL);
        navigation.setBackground(BrowserUi.surface(this,Color.WHITE,18,BrowserUi.LINE));
        bottom.addView(navigation,new LinearLayout.LayoutParams(-1,dp(52)));
        BrowserUi.Icon search = new BrowserUi.Icon(this,"search"); search.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        navigation.addView(search,new LinearLayout.LayoutParams(dp(44),dp(48)));
        address = new EditText(this); address.setSingleLine(true); address.setTextSize(15); address.setTextColor(BrowserUi.INK);
        address.setHintTextColor(BrowserUi.MUTED); address.setHint("Search or enter website"); address.setContentDescription("Search or website address");
        address.setBackgroundColor(Color.TRANSPARENT); address.setPadding(0,0,0,0); address.setSelectAllOnFocus(true);
        address.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_VARIATION_URI); address.setImeOptions(EditorInfo.IME_ACTION_GO);
        navigation.addView(address,new LinearLayout.LayoutParams(0,-1,1));
        address.setOnEditorActionListener((v,action,event) -> { if(action==EditorInfo.IME_ACTION_GO || (event!=null && event.getKeyCode()==KeyEvent.KEYCODE_ENTER && event.getAction()==KeyEvent.ACTION_UP)) { navigate(); return true; } return false; });
        button(navigation,"go",v -> navigate()).setContentDescription("Go to website or search");
        LinearLayout tools = new LinearLayout(this); tools.setGravity(Gravity.CENTER_VERTICAL); bottom.addView(tools,new LinearLayout.LayoutParams(-1,dp(56)));
        backButton=button(tools,"back",v -> { if(current().canGoBack()) current().goBack(); }); backButton.setContentDescription("Back");
        forwardButton=button(tools,"forward",v -> { if(current().canGoForward()) current().goForward(); }); forwardButton.setContentDescription("Forward");
        button(tools,"home",v -> current().loadUrl(HOME)).setContentDescription("Mars home");
        reloadButton=button(tools,"reload",v -> { if(current().getProgress()<100) current().stopLoading(); else current().reload(); }); reloadButton.setContentDescription("Reload or stop");
        tabButton=button(tools,"1",v -> showTabs());
        for(int i=0;i<tools.getChildCount();i++) tools.getChildAt(i).setLayoutParams(new LinearLayout.LayoutParams(0,dp(48),1));
        root.setFocusableInTouchMode(true); root.requestFocus();
        int restoredIndex = prefs.getInt("selected",0);
        try {
            JSONArray saved = new JSONArray(prefs.getString("tabs","[]"));
            for(int i=0;i<Math.min(saved.length(),30);i++) newTab(safeUrl(saved.getString(i)));
        } catch(JSONException ignored) {}
        if(tabs.isEmpty()) newTab(HOME);
        select(Math.min(restoredIndex,tabs.size()-1));
    }
    private int dp(int n) { return (int)(n*getResources().getDisplayMetrics().density); }
    private LinearLayout row() { LinearLayout r=new LinearLayout(this); r.setGravity(Gravity.CENTER_VERTICAL); root.addView(r,new LinearLayout.LayoutParams(-1,-2)); return r; }
    private Button button(LinearLayout row,String icon,View.OnClickListener click) {
        Button b=new BrowserUi.Icon(this,icon);
        LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(dp(48),dp(48));
        row.addView(b,params); b.setOnClickListener(click); return b;
    }
    private WebView current() { return tabs.get(selected); }
    private String safeUrl(String url) { return url!=null && (url.startsWith("https://") || url.startsWith("http://")) ? url : HOME; }
    private void newTab(String url) {
        if(tabs.size()>=30) { Toast.makeText(this,"Close a tab before opening another",Toast.LENGTH_SHORT).show(); return; }
        WebView web = new WebView(this);
        WebSettings settings=web.getSettings(); settings.setJavaScriptEnabled(true); settings.setDomStorageEnabled(true); settings.setAllowFileAccess(false); settings.setAllowContentAccess(false); settings.setSupportZoom(true); settings.setBuiltInZoomControls(true); settings.setDisplayZoomControls(false); settings.setUseWideViewPort(true); settings.setLoadWithOverviewMode(true);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view,WebResourceRequest request) {
                String scheme=request.getUrl().getScheme();
                if("http".equals(scheme) || "https".equals(scheme)) return false;
                if(request.isForMainFrame() && ("mailto".equals(scheme) || "tel".equals(scheme))) {
                    try { startActivity(new Intent(Intent.ACTION_VIEW,request.getUrl())); } catch(ActivityNotFoundException ignored) { Toast.makeText(MainActivity.this,"No app available for this link",Toast.LENGTH_SHORT).show(); }
                }
                return true;
            }
            @Override public void onPageStarted(WebView view,String url,android.graphics.Bitmap favicon) { if(view==current()) refresh(); }
            @Override public void onPageFinished(WebView view,String url) { if(view==current()) refresh(); save(); }
            @Override public void onReceivedError(WebView view,WebResourceRequest request,WebResourceError error) { if(request.isForMainFrame()) Toast.makeText(MainActivity.this,"Could not load page. Check your connection and try again.",Toast.LENGTH_SHORT).show(); }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public void onProgressChanged(WebView view,int value) { if(!tabs.isEmpty() && view==current()) { progress.setProgress(value); progress.setVisibility(value==100 ? View.INVISIBLE : View.VISIBLE); reloadButton.setText(value==100 ? "reload" : "close"); } }
            @Override public void onReceivedTitle(WebView view,String title) { save(); }
        });
        tabs.add(web); select(tabs.size()-1); web.loadUrl(safeUrl(url)); save();
    }
    private void select(int index) { selected=Math.max(0,index); pages.removeAllViews(); pages.addView(current(),new FrameLayout.LayoutParams(-1,-1)); refresh(); save(); }
    private void refresh() { if(!address.hasFocus()) address.setText(current().getUrl()); tabButton.setText(String.valueOf(tabs.size())); tabButton.setContentDescription("Tabs: "+tabs.size()); reloadButton.setText(current().getProgress()==100 ? "reload" : "close"); backButton.setEnabled(current().canGoBack()); forwardButton.setEnabled(current().canGoForward()); progress.setProgress(current().getProgress()); progress.setVisibility(current().getProgress()==100 ? View.INVISIBLE : View.VISIBLE); }
    private void navigate() {
        String text=address.getText().toString().trim(); if(text.isEmpty()) return;
        String url;
        if(text.startsWith("https://") || text.startsWith("http://")) url=text;
        else if(!text.contains(" ") && text.matches("[A-Za-z0-9.-]+\\.[A-Za-z]{2,}([/:?#].*)?")) url="https://"+text;
        else { String engine=prefs.getString("engine","Mars"); String base=engine.equals("Google") ? "https://www.google.com/search?q=" : engine.equals("DuckDuckGo") ? "https://duckduckgo.com/?q=" : HOME+"/search?q="; url=base+Uri.encode(text); }
        address.clearFocus(); ((InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(address.getWindowToken(),0); current().loadUrl(url);
    }
    private Dialog sheet(String title, String subtitle, LinearLayout content) {
        Dialog dialog=new Dialog(this);
        LinearLayout shell=new LinearLayout(this); shell.setOrientation(LinearLayout.VERTICAL);
        shell.setPadding(dp(20),dp(12),dp(20),dp(24));
        shell.setBackground(BrowserUi.surface(this,Color.WHITE,28,0));
        View handle=new View(this); handle.setBackground(BrowserUi.surface(this,BrowserUi.LINE,3,0));
        LinearLayout.LayoutParams handleParams=new LinearLayout.LayoutParams(dp(32),dp(4)); handleParams.gravity=Gravity.CENTER; handleParams.bottomMargin=dp(16); shell.addView(handle,handleParams);
        LinearLayout heading=new LinearLayout(this); heading.setGravity(Gravity.CENTER_VERTICAL);
        TextView name=BrowserUi.text(this,title,26,BrowserUi.INK,true); name.setLetterSpacing(-0.03f);
        heading.addView(name,new LinearLayout.LayoutParams(0,-2,1));
        button(heading,"close",v->dialog.dismiss()).setContentDescription("Close panel"); shell.addView(heading);
        TextView detail=BrowserUi.text(this,subtitle,14,BrowserUi.MUTED,false); detail.setPadding(0,0,0,dp(20)); shell.addView(detail);
        ScrollView scroll=new ScrollView(this); scroll.setFillViewport(false); scroll.addView(content); shell.addView(scroll,new LinearLayout.LayoutParams(-1,-2));
        dialog.setContentView(shell); Window window=dialog.getWindow();
        window.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
        window.setNavigationBarColor(Color.WHITE); window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
        window.addFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND); window.setDimAmount(0.32f); window.setGravity(Gravity.BOTTOM);
        dialog.setOnShowListener(d->{ window.setLayout(-1,-2); int max=(int)(getResources().getDisplayMetrics().heightPixels*0.82); shell.post(()->{if(shell.getHeight()>max) {scroll.getLayoutParams().height=Math.max(dp(100),max-dp(148));scroll.requestLayout();}}); });
        return dialog;
    }
    private LinearLayout column() { LinearLayout list=new LinearLayout(this); list.setOrientation(LinearLayout.VERTICAL); return list; }
    private TextView action(LinearLayout list,String label,View.OnClickListener click) {
        TextView view=BrowserUi.text(this,label,16,Color.WHITE,true); view.setGravity(Gravity.CENTER); view.setBackground(BrowserUi.touch(this,BrowserUi.INK,16,0));
        LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(-1,dp(52)); params.topMargin=dp(12); list.addView(view,params);view.setOnClickListener(click);return view;
    }
    private String domain(WebView web) { String host=Uri.parse(safeUrl(web.getUrl())).getHost(); return host==null?"New tab":host; }
    private void showTabs() {
        LinearLayout list=column(); Dialog dialog=sheet("Your tabs",tabs.size()+" open · Pick up where you left off",list);
        for(int i=0;i<tabs.size();i++) {
            final int index=i; WebView web=tabs.get(i);
            LinearLayout card=new LinearLayout(this);card.setGravity(Gravity.CENTER_VERTICAL);card.setPadding(dp(14),dp(10),dp(4),dp(10));
            card.setBackground(BrowserUi.touch(this,i==selected?BrowserUi.SURFACE:Color.WHITE,18,i==selected?BrowserUi.INK:BrowserUi.LINE));
            LinearLayout.LayoutParams cardParams=new LinearLayout.LayoutParams(-1,-2);cardParams.bottomMargin=dp(10);list.addView(card,cardParams);
            ImageView favicon=new ImageView(this); if(web.getFavicon()!=null) favicon.setImageBitmap(web.getFavicon()); else favicon.setImageResource(com.yavqo.saturn.R.drawable.saturn_logo);
            LinearLayout.LayoutParams iconParams=new LinearLayout.LayoutParams(dp(28),dp(28));iconParams.rightMargin=dp(14);card.addView(favicon,iconParams);
            LinearLayout labels=column(); String title=web.getTitle();TextView name=BrowserUi.text(this,title==null?"New tab":title,16,BrowserUi.INK,true);
            name.setMaxLines(1);name.setEllipsize(android.text.TextUtils.TruncateAt.END); labels.addView(name);
            TextView host=BrowserUi.text(this,(i==selected?"Current · ":"")+domain(web),13,BrowserUi.MUTED,false);host.setMaxLines(1);host.setEllipsize(android.text.TextUtils.TruncateAt.END);labels.addView(host);
            card.addView(labels,new LinearLayout.LayoutParams(0,-2,1));card.setOnClickListener(v->{select(index);dialog.dismiss();});
            button(card,"close",v->{WebView removed=tabs.remove(index);pages.removeAllViews();removed.destroy();if(tabs.isEmpty())newTab(HOME);else {if(index<selected)selected--;select(Math.min(selected,tabs.size()-1));}dialog.dismiss();showTabs();}).setContentDescription("Close "+(title==null?"tab":title));
        }
        action(list,"New tab",v->{dialog.dismiss();newTab(HOME);});dialog.show();
    }
    private void settingRow(LinearLayout list,String title,String detail,String trailing,View.OnClickListener click) {
        LinearLayout row=new LinearLayout(this);row.setGravity(Gravity.CENTER_VERTICAL);row.setPadding(dp(16),dp(16),dp(16),dp(16));row.setBackground(BrowserUi.touch(this,BrowserUi.SURFACE,16,0));
        LinearLayout labels=column();labels.addView(BrowserUi.text(this,title,16,BrowserUi.INK,true));TextView sub=BrowserUi.text(this,detail,13,BrowserUi.MUTED,false);sub.setPadding(0,dp(4),0,0);labels.addView(sub);row.addView(labels,new LinearLayout.LayoutParams(0,-2,1));
        TextView value=BrowserUi.text(this,trailing,14,BrowserUi.MUTED,true);value.setPadding(dp(12),0,0,0);row.addView(value);
        LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(-1,-2);params.bottomMargin=dp(10);list.addView(row,params);row.setOnClickListener(click);
    }
    private void showSettings() {
        LinearLayout list=column();Dialog dialog=sheet("Settings","Make Saturn feel like yours",list);
        settingRow(list,"Search engine","Used when you search from the address bar",prefs.getString("engine","Mars"),v->{dialog.dismiss();showSearchSettings();});
        settingRow(list,"Clear browsing data","Cookies, cache and website storage","",v->{dialog.dismiss();showClearData();});
        TextView about=BrowserUi.text(this,"Saturn for Android  0.4.0\nAndroid preview · Elaine is available on desktop",13,BrowserUi.MUTED,false);about.setPadding(dp(4),dp(16),dp(4),dp(8));about.setLineSpacing(dp(5),1);list.addView(about);dialog.show();
    }
    private void showSearchSettings() {
        LinearLayout list=column();Dialog dialog=sheet("Search engine","Choose where your searches begin",list);
        String selectedEngine=prefs.getString("engine","Mars");
        for(String engine:new String[]{"Mars","Google","DuckDuckGo"}) settingRow(list,engine,engine.equals("Mars")?"The Saturn default":engine.equals("Google")?"Google Search":"DuckDuckGo Search",engine.equals(selectedEngine)?"Selected":"",v->{prefs.edit().putString("engine",engine).apply();dialog.dismiss();showSettings();});
        dialog.show();
    }
    private void showClearData() {
        LinearLayout list=column();Dialog dialog=sheet("Clear browsing data?","You’ll be signed out of websites",list);
        TextView detail=BrowserUi.text(this,"Remove cookies, cached pages and website storage from this device.",16,BrowserUi.MUTED,false);detail.setLineSpacing(dp(4),1);list.addView(detail);
        action(list,"Clear browsing data",v->{for(WebView web:tabs){web.stopLoading();web.clearCache(true);web.clearHistory();}WebStorage.getInstance().deleteAllData();CookieManager.getInstance().removeAllCookies(done->{CookieManager.getInstance().flush();Toast.makeText(this,"Browsing data cleared",Toast.LENGTH_SHORT).show();});dialog.dismiss();});
        TextView cancel=BrowserUi.text(this,"Keep browsing data",16,BrowserUi.INK,true);cancel.setGravity(Gravity.CENTER);list.addView(cancel,new LinearLayout.LayoutParams(-1,dp(52)));cancel.setBackground(BrowserUi.touch(this,Color.WHITE,16,0));cancel.setOnClickListener(v->dialog.dismiss());dialog.show();
    }
    private void save() { JSONArray urls=new JSONArray(); for(WebView web:tabs) urls.put(safeUrl(web.getUrl())); prefs.edit().putString("tabs",urls.toString()).putInt("selected",selected).apply(); }
    @Override protected void onPause() { super.onPause(); save(); for(WebView web:tabs) web.onPause(); }
    @Override protected void onResume() { super.onResume(); for(WebView web:tabs) web.onResume(); }
    @Override public void onBackPressed() { if(current().canGoBack()) current().goBack(); else super.onBackPressed(); }
    @Override protected void onDestroy() { pages.removeAllViews(); for(WebView web:tabs) web.destroy(); super.onDestroy(); }
}
