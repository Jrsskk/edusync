<?php

namespace App\Notifications;

use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;
use Illuminate\Support\Facades\URL;

class StudentEmailVerificationNotification extends Notification
{
    use Queueable;

    public function via(object $notifiable): array
    {
        return ['mail'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $url = URL::temporarySignedRoute(
            'api.v1.email.verify',
            now()->addMinutes(60),
            [
                'id' => $notifiable->getKey(),
                'hash' => sha1($notifiable->email),
            ],
        );

        return (new MailMessage)
            ->subject('Verify your EduSync email')
            ->greeting('Hello '.$notifiable->full_name.',')
            ->line('Verify your email address to complete your EduSync Student account setup.')
            ->action('Verify email address', $url)
            ->line('This link expires in 60 minutes. If you did not create this account, you can ignore this email.');
    }
}
