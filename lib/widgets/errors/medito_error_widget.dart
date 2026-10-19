import 'package:medito/constants/constants.dart';
import 'package:medito/exceptions/app_error.dart';
import 'package:medito/l10n/app_localizations.dart';
import 'package:medito/providers/providers.dart';
import 'package:medito/routes/routes.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../views/downloads/downloads_view.dart';

class MeditoErrorWidget extends ConsumerWidget {
  const MeditoErrorWidget({
    super.key,
    required this.onTap,
    required this.error,
    this.isLoading = false,
    this.shouldShowCheckDownloadButton = false,
    this.isScaffold = true,
  });

  final void Function() onTap;
  final AppError error;
  final bool isLoading;
  final bool shouldShowCheckDownloadButton;
  final bool isScaffold;

  String _getErrorMessage(BuildContext context) {
    return switch (error) {
      YoutubeUnavailableError() => AppLocalizations.of(
        context,
      )!.youtubeUnavailable,
      NetworkConnectionError() => AppLocalizations.of(
        context,
      )!.errorNoInternetMessage,
      TimeoutError() => AppLocalizations.of(context)!.errorTimeoutMessage,
      NotFoundError() => AppLocalizations.of(context)!.errorNotFoundMessage,
      ServerError() => AppLocalizations.of(context)!.errorServerMessage,
      UnknownError() => AppLocalizations.of(context)!.errorUnknownMessage,
      _ => AppLocalizations.of(context)!.errorUnknownMessage,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var uiState = ref.watch(
      meditoErrorWidgetProvider(
        MeditoErrorWidgetUIState(
          shouldShowCheckDownloadButton,
          _getErrorMessage(context),
        ),
      ),
    );
    var textStyle = Theme.of(context).textTheme.headlineMedium;

    var mainBody = _mainBody(
      context,
      uiState.message,
      uiState.shouldShowCheckDownloadButton,
      textStyle,
    );

    if (isScaffold) {
      return Scaffold(backgroundColor: ColorConstants.ebony, body: mainBody);
    }

    return mainBody;
  }

  SizedBox _mainBody(
    BuildContext context,
    String message,
    bool isShowCheckDownload,
    TextStyle? textStyle,
  ) {
    return SizedBox(
      width: MediaQuery.of(context).size.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: padding16,
          vertical: padding16,
        ),
        child: Column(
          mainAxisSize: isScaffold ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            RichText(
              text: TextSpan(
                text: '$message. ',
                style: textStyle,
                children: <TextSpan>[
                  if (isShowCheckDownload)
                    TextSpan(
                      text: '${AppLocalizations.of(context)!.meanWhileListen} ',
                      style: textStyle,
                    ),
                  if (isShowCheckDownload)
                    TextSpan(
                      text: AppLocalizations.of(
                        context,
                      )!.downloads.toLowerCase(),
                      style: textStyle?.copyWith(
                        decoration: TextDecoration.underline,
                        color: ColorConstants.accentDark,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const DownloadsView(),
                          ),
                        ),
                    ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            height16,
            Column(
              spacing: 4,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 300,
                  child: OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(AppLocalizations.of(context)!.retry),
                  ),
                ),
                SizedBox(
                  width: 300,
                  child: ElevatedButton(
                    onPressed: () {
                      handleNavigation(TypeConstants.flow, [
                        TypeConstants.downloads,
                      ], context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.brandAccent,
                      foregroundColor: context.onBrandAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(AppLocalizations.of(context)!.goToDownloads),
                  ),
                ),
                // The timer plays local audio, so it works offline too.
                SizedBox(
                  width: 300,
                  child: OutlinedButton(
                    onPressed: () {
                      handleNavigation(TypeConstants.route, [
                        RouteConstants.timer,
                      ], context);
                    },
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(AppLocalizations.of(context)!.openTimer),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
