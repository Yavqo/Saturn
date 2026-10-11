package com.yavqo.saturn;

import android.content.Context;
import android.graphics.*;
import android.graphics.drawable.*;
import android.content.res.ColorStateList;
import android.view.*;
import android.widget.*;

/** Shared surfaces and drawn icons keep the browser chrome consistent. */
final class BrowserUi {
    static final int INK=Color.rgb(28,32,39), MUTED=Color.rgb(99,108,121), SURFACE=Color.rgb(245,246,248), LINE=Color.rgb(224,227,232);
    static int dp(Context c,int n) { return Math.round(n*c.getResources().getDisplayMetrics().density); }
    static GradientDrawable surface(Context c,int color,int radius,int border) {
        GradientDrawable d=new GradientDrawable(); d.setColor(color); d.setCornerRadius(dp(c,radius));
        if(border!=0) d.setStroke(dp(c,1),border); return d;
    }
    static android.graphics.drawable.Drawable touch(Context c,int color,int radius,int border) {
        return new RippleDrawable(ColorStateList.valueOf(0x18000000),surface(c,color,radius,border),surface(c,Color.WHITE,radius,0));
    }
    static TextView text(Context c,String value,int size,int color,boolean bold) {
        TextView t=new TextView(c); t.setText(value); t.setTextSize(size); t.setTextColor(color); t.setFontFeatureSettings("kern");
        t.setTypeface(Typeface.create(bold?"sans-serif-medium":"sans-serif",Typeface.NORMAL)); return t;
    }
    static final class Icon extends Button {
        private String kind;
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG);
        Icon(Context c,String icon) {
            super(c); kind=icon; setPadding(0,0,0,0); setMinWidth(0); setMinimumWidth(0); setMinHeight(0); setMinimumHeight(0);
            setBackground(touch(c,Color.TRANSPARENT,14,0)); setContentDescription(icon); setAllCaps(false);
        }
        @Override public void setText(CharSequence value,BufferType type) { kind=value.toString(); invalidate(); }
        @Override protected void onDraw(Canvas canvas) {
            canvas.save(); float scale=Math.min(getWidth(),getHeight())/48f; canvas.translate(getWidth()/2f,getHeight()/2f); canvas.scale(scale,scale);
            paint.setColor(isEnabled()?INK:0xffb9bec6); paint.setStrokeWidth(1.8f); paint.setStrokeCap(Paint.Cap.ROUND); paint.setStrokeJoin(Paint.Join.ROUND); paint.setStyle(Paint.Style.STROKE);
            Path p=new Path();
            switch(kind==null?"":kind) {
                case "back": p.moveTo(3,-7); p.lineTo(-4,0); p.lineTo(3,7); canvas.drawPath(p,paint); break;
                case "forward": p.moveTo(-3,-7); p.lineTo(4,0); p.lineTo(-3,7); canvas.drawPath(p,paint); break;
                case "close": canvas.drawLine(-5,-5,5,5,paint); canvas.drawLine(-5,5,5,-5,paint); break;
                case "add": canvas.drawLine(-7,0,7,0,paint); canvas.drawLine(0,-7,0,7,paint); break;
                case "go": canvas.drawLine(-7,0,7,0,paint); p.moveTo(1,-6); p.lineTo(7,0); p.lineTo(1,6); canvas.drawPath(p,paint); break;
                case "home": p.moveTo(-9,-1); p.lineTo(0,-9); p.lineTo(9,-1); p.moveTo(-6,-3); p.lineTo(-6,8); p.lineTo(6,8); p.lineTo(6,-3); canvas.drawPath(p,paint); break;
                case "reload": canvas.drawArc(-8,-8,8,8,35,285,false,paint); p.moveTo(8,-8); p.lineTo(8,-1); p.lineTo(1,-1); canvas.drawPath(p,paint); break;
                case "settings": canvas.drawCircle(0,0,4,paint); canvas.drawCircle(0,0,9,paint); for(int i=0;i<8;i++) {canvas.save();canvas.rotate(i*45);canvas.drawLine(0,-9,0,-12,paint);canvas.restore();} break;
                case "search": canvas.drawCircle(-2,-2,6,paint); canvas.drawLine(3,3,8,8,paint); break;
                default: canvas.drawRoundRect(-9,-10,9,10,4,4,paint); paint.setStyle(Paint.Style.FILL); paint.setTextSize(12);paint.setTypeface(Typeface.create("sans-serif-medium",0));paint.setTextAlign(Paint.Align.CENTER);canvas.drawText(kind==null?"1":kind,0,4,paint);
            }
            canvas.restore();
        }
    }
}
