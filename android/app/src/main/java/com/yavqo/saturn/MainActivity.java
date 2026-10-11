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
                v.setPadding(bars.left, bars.top, bars.right, bars.bottom);
            } else { v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(), insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom()); }
            return insets;
        });
        setContentView(root);
        LinearLayout header = row();
        TextView brand = new TextView(this); brand.setText("SATURN"); brand.setTextColor(Color.BLACK); brand.setTextSize(18); brand.setPadding(dp(12),0,dp(8),0);
        header.addView(brand, new LinearLayout.LayoutParams(0,dp(48),1)); brand.setGravity(Gravity.CENTER_VERTICAL);
        tabButton = button(header,"1", v -> showTabs());
        button(header,"⚙", v -> showSettings()).setContentDescription("Settings");
        LinearLayout navigation = row();
        address = new EditText(this); address.setSingleLine(true); address.setTextSize(15); address.setHint("Search or enter address"); address.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_VARIATION_URI); address.setImeOptions(EditorInfo.IME_ACTION_GO);
        navigation.addView(address,new LinearLayout.LayoutParams(0,dp(52),1));
        address.setOnEditorActionListener((v,action,event) -> { if(action==EditorInfo.IME_ACTION_GO || (event!=null && event.getKeyCode()==KeyEvent.KEYCODE_ENTER && event.getAction()==KeyEvent.ACTION_UP)) { navigate(); return true; } return false; });
        button(navigation,"Go",v -> navigate());
        progress = new ProgressBar(this,null,android.R.attr.progressBarStyleHorizontal); progress.setMax(100); root.addView(progress,new LinearLayout.LayoutParams(-1,dp(3)));
        pages = new FrameLayout(this); root.addView(pages,new LinearLayout.LayoutParams(-1,0,1));
        LinearLayout tools = row();
        backButton=button(tools,"‹",v -> { if(current().canGoBack()) current().goBack(); }); backButton.setContentDescription("Back");
        forwardButton=button(tools,"›",v -> { if(current().canGoForward()) current().goForward(); }); forwardButton.setContentDescription("Forward");
        reloadButton=button(tools,"↻",v -> { if(current().getProgress()<100) current().stopLoading(); else current().reload(); }); reloadButton.setContentDescription("Reload or stop");
        button(tools,"Home",v -> current().loadUrl(HOME));
        button(tools,"+",v -> newTab(HOME));
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
    private Button button(LinearLayout row,String text,View.OnClickListener click) { Button b=new Button(this); b.setText(text); b.setTextColor(Color.BLACK); b.setMinWidth(0); b.setMinimumWidth(0); row.addView(b,new LinearLayout.LayoutParams(-2,dp(48))); b.setOnClickListener(click); return b; }
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
            @Override public void onProgressChanged(WebView view,int value) { if(!tabs.isEmpty() && view==current()) { progress.setProgress(value); progress.setVisibility(value==100 ? View.INVISIBLE : View.VISIBLE); reloadButton.setText(value==100 ? "↻" : "×"); } }
            @Override public void onReceivedTitle(WebView view,String title) { save(); }
        });
        tabs.add(web); select(tabs.size()-1); web.loadUrl(safeUrl(url)); save();
    }
    private void select(int index) { selected=Math.max(0,index); pages.removeAllViews(); pages.addView(current(),new FrameLayout.LayoutParams(-1,-1)); refresh(); save(); }
    private void refresh() { if(!address.hasFocus()) address.setText(current().getUrl()); tabButton.setText(String.valueOf(tabs.size())); tabButton.setContentDescription("Tabs: "+tabs.size()); backButton.setEnabled(current().canGoBack()); forwardButton.setEnabled(current().canGoForward()); progress.setProgress(current().getProgress()); progress.setVisibility(current().getProgress()==100 ? View.INVISIBLE : View.VISIBLE); }
    private void navigate() {
        String text=address.getText().toString().trim(); if(text.isEmpty()) return;
        String url;
        if(text.startsWith("https://") || text.startsWith("http://")) url=text;
        else if(!text.contains(" ") && text.matches("[A-Za-z0-9.-]+\\.[A-Za-z]{2,}([/:?#].*)?")) url="https://"+text;
        else { String engine=prefs.getString("engine","Mars"); String base=engine.equals("Google") ? "https://www.google.com/search?q=" : engine.equals("DuckDuckGo") ? "https://duckduckgo.com/?q=" : HOME+"/search?q="; url=base+Uri.encode(text); }
        address.clearFocus(); ((InputMethodManager)getSystemService(INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(address.getWindowToken(),0); current().loadUrl(url);
    }
    private void showTabs() {
        LinearLayout list=new LinearLayout(this); list.setOrientation(LinearLayout.VERTICAL);
        AlertDialog dialog=new AlertDialog.Builder(this).setTitle("Tabs").setView(list).setPositiveButton("New tab",(d,w)->newTab(HOME)).setNegativeButton("Done",null).create();
        for(int i=0;i<tabs.size();i++) {
            final int index=i; LinearLayout row=new LinearLayout(this); Button title=new Button(this); String name=tabs.get(i).getTitle(); title.setText((i==selected ? "● " : "")+(name==null ? "New tab" : name)); title.setMaxLines(2); row.addView(title,new LinearLayout.LayoutParams(0,-2,1)); title.setOnClickListener(v->{select(index); dialog.dismiss();});
            Button close=new Button(this); close.setText("×"); close.setContentDescription("Close tab"); row.addView(close,new LinearLayout.LayoutParams(dp(56),-2)); close.setOnClickListener(v->{WebView removed=tabs.remove(index); pages.removeAllViews(); removed.destroy(); if(tabs.isEmpty()) newTab(HOME); else { if(index<selected) selected--; select(Math.min(selected,tabs.size()-1)); } dialog.dismiss(); showTabs();}); list.addView(row);
        }
        ScrollView scroll=new ScrollView(this); scroll.addView(list); dialog.setView(scroll); dialog.show();
    }
    private void showSettings() {
        String engine=prefs.getString("engine","Mars"); String[] items={"Search engine: "+engine,"Clear browsing data","About Saturn"};
        new AlertDialog.Builder(this).setTitle("Settings").setItems(items,(d,which)->{
            if(which==0) { String[] engines={"Mars","Google","DuckDuckGo"}; int checked=Arrays.asList(engines).indexOf(engine); new AlertDialog.Builder(this).setTitle("Default search engine").setSingleChoiceItems(engines,checked,(choice,n)->{prefs.edit().putString("engine",engines[n]).apply(); choice.dismiss();}).setNegativeButton("Cancel",null).show(); }
            if(which==1) new AlertDialog.Builder(this).setTitle("Clear browsing data?").setMessage("This removes cookies, cached pages and website storage, and signs you out of websites.").setPositiveButton("Clear",(confirm,n)->{for(WebView web:tabs) {web.stopLoading(); web.clearCache(true); web.clearHistory();} WebStorage.getInstance().deleteAllData(); CookieManager.getInstance().removeAllCookies(done->{CookieManager.getInstance().flush(); Toast.makeText(this,"Browsing data cleared",Toast.LENGTH_SHORT).show();});}).setNegativeButton("Cancel",null).show();
            if(which==2) new AlertDialog.Builder(this).setTitle("Saturn 0.4.0 for Android").setMessage("Android preview with Mars search, tabs and browser settings. Elaine is available in the desktop app.").setPositiveButton("OK",null).show();
        }).setNegativeButton("Done",null).show();
    }
    private void save() { JSONArray urls=new JSONArray(); for(WebView web:tabs) urls.put(safeUrl(web.getUrl())); prefs.edit().putString("tabs",urls.toString()).putInt("selected",selected).apply(); }
    @Override protected void onPause() { super.onPause(); save(); for(WebView web:tabs) web.onPause(); }
    @Override protected void onResume() { super.onResume(); for(WebView web:tabs) web.onResume(); }
    @Override public void onBackPressed() { if(current().canGoBack()) current().goBack(); else super.onBackPressed(); }
    @Override protected void onDestroy() { pages.removeAllViews(); for(WebView web:tabs) web.destroy(); super.onDestroy(); }
}
