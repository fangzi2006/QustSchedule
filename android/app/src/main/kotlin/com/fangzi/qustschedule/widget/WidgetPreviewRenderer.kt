package com.fangzi.qustschedule.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.widget.BaseAdapter
import android.widget.FrameLayout
import android.widget.ListView
import android.widget.RemoteViews
import com.fangzi.qustschedule.R
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

/**
 * 桌面小组件真实原生离屏预览渲染器：
 * 直接复用与系统桌面完全相同的 [WeekGridCanvasRenderer]、[TodayWidgetProvider]、
 * [TodayItemViewBinder] 与 [NextClassWidgetProvider] 渲染逻辑输出 PNG 位图，
 * 确保软件内预览在系统字体、Material You 取色、圆角裁切与换行截断上与桌面 100% 一致。
 */
internal object WidgetPreviewRenderer {

    private val mainHandler = Handler(Looper.getMainLooper())

    fun renderPngAsync(
        context: Context,
        kind: String,
        payloadJson: String,
        widthDp: Int,
        heightDp: Int,
        nowMs: Long,
        isDarkWallpaper: Boolean,
        onComplete: (ByteArray?) -> Unit,
    ) {
        val appContext = context.applicationContext
        val safeW = widthDp.coerceIn(80, 480)
        val safeH = heightDp.coerceIn(48, 480)

        WidgetWorker.execute {
            val snapshot = WidgetSnapshotModel.parse(payloadJson)
            val style = snapshot?.styleOf(kind) ?: WidgetStyleData.defaultFor(kind)
            val theme = WidgetThemeResolver.resolve(
                context = appContext,
                style = style,
                nightModeOverride = isDarkWallpaper,
            )

            if (kind == KIND_WEEK) {
                val png = try {
                    val vm = WidgetContentResolver.resolveWeek(snapshot, style, nowMs)
                    val bitmap = WeekGridCanvasRenderer.render(
                        context = appContext,
                        style = style,
                        theme = theme,
                        viewModel = vm,
                        widthDp = safeW,
                        heightDp = safeH,
                    )
                    encodeAndRecycle(bitmap)
                } catch (_: Throwable) {
                    null
                }
                onComplete(png)
                return@execute
            }

            // Today / Next 复用原生 RemoteViews，在后台预构建 RemoteViews 与背景位图，
            // 再切主线程完成离屏 inflate/measure/layout/draw，最后回后台编码 PNG。
            val prepared: PreparedRemotePreview? = try {
                when (kind) {
                    KIND_TODAY -> {
                        val vm = WidgetContentResolver.resolveToday(snapshot, style, nowMs)
                        val isNarrow = TodayItemViewBinder.isNarrowWidth(safeW)
                        val outerViews = TodayWidgetProvider.buildRemoteViews(
                            context = appContext,
                            style = style,
                            theme = theme,
                            vm = vm,
                            wDp = safeW,
                            hDp = safeH,
                            nowMs = nowMs,
                            isNarrow = isNarrow,
                            bindList = null,
                        )
                        val itemViews = vm.items.map { item ->
                            TodayItemViewBinder.buildItemView(
                                context = appContext,
                                item = item,
                                style = style,
                                theme = theme,
                                nowMs = nowMs,
                                isNarrow = isNarrow,
                            )
                        }
                        PreparedRemotePreview(outerViews, itemViews)
                    }

                    KIND_NEXT -> {
                        val vm = WidgetContentResolver.resolveNext(snapshot, style, nowMs)
                        val outerViews = NextClassWidgetProvider.buildRemoteViews(
                            context = appContext,
                            style = style,
                            theme = theme,
                            vm = vm,
                            wDp = safeW,
                            hDp = safeH,
                        )
                        PreparedRemotePreview(outerViews, emptyList())
                    }

                    else -> null
                }
            } catch (_: Throwable) {
                null
            }

            if (prepared == null) {
                onComplete(null)
                return@execute
            }

            mainHandler.post {
                val renderedBitmap = try {
                    drawRemoteViewsToBitmap(appContext, prepared, safeW, safeH)
                } catch (_: Throwable) {
                    null
                }
                if (renderedBitmap == null) {
                    onComplete(null)
                    return@post
                }
                WidgetWorker.execute {
                    val png = try {
                        encodeAndRecycle(renderedBitmap)
                    } catch (_: Throwable) {
                        if (!renderedBitmap.isRecycled) renderedBitmap.recycle()
                        null
                    }
                    onComplete(png)
                }
            }
        }
    }

    private data class PreparedRemotePreview(
        val outerViews: RemoteViews,
        val todayItemViews: List<RemoteViews>,
    )

    private fun drawRemoteViewsToBitmap(
        context: Context,
        prepared: PreparedRemotePreview,
        widthDp: Int,
        heightDp: Int,
    ): Bitmap {
        val density = context.resources.displayMetrics.density.coerceAtLeast(1f)
        val widthPx = (widthDp * density).roundToInt().coerceAtLeast(1)
        val heightPx = (heightDp * density).roundToInt().coerceAtLeast(1)

        val container = FrameLayout(context)
        val rootView = prepared.outerViews.apply(context, container)

        if (prepared.todayItemViews.isNotEmpty()) {
            val listView = rootView.findViewById<ListView>(R.id.widget_today_list)
            if (listView != null) {
                listView.adapter = object : BaseAdapter() {
                    override fun getCount(): Int = prepared.todayItemViews.size
                    override fun getItem(position: Int): Any = position
                    override fun getItemId(position: Int): Long = position.toLong()
                    override fun getView(
                        position: Int,
                        convertView: View?,
                        parent: ViewGroup,
                    ): View = prepared.todayItemViews[position].apply(context, parent)
                }
            }
        }

        val wSpec = View.MeasureSpec.makeMeasureSpec(widthPx, View.MeasureSpec.EXACTLY)
        val hSpec = View.MeasureSpec.makeMeasureSpec(heightPx, View.MeasureSpec.EXACTLY)
        rootView.measure(wSpec, hSpec)
        rootView.layout(0, 0, widthPx, heightPx)

        val outBitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(outBitmap)
        rootView.draw(canvas)
        return outBitmap
    }

    private fun encodeAndRecycle(bitmap: Bitmap): ByteArray {
        return try {
            val out = ByteArrayOutputStream(32 * 1024)
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        } finally {
            if (!bitmap.isRecycled) {
                bitmap.recycle()
            }
        }
    }
}
